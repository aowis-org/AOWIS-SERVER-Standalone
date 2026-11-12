#include <aowis/map/maptiles.h>
#include <aowis/map/provider_catalog.h>
#include <aowis/map/settings_repository.h>

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QHostAddress>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QThread>
#include <QTimer>

#include <cstdio>
#include <memory>

namespace
{
constexpr const char *ProviderId = "bb03d866-1ee7-4511-98dc-9b28db458824";

bool check(bool value, const char *message)
{
    if (!value) std::fprintf(stderr, "FAILED: %s\n", message);
    return value;
}

QByteArray samplePng()
{
    return QByteArray::fromBase64(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j"
        "mZkAAAAASUVORK5CYII=");
}

// These are actual HTTP peers, not mocked responses inside MapTiles. Each
// simulates the MAP catalog and raster endpoints with separate read keys.
class MapPeer final : public QTcpServer
{
public:
    QByteArray expected_key;
    QByteArray catalog;
    QByteArray fingerprint;
    bool tile_enabled = true;
    int catalog_requests = 0;
    int tile_requests = 0;

    bool start() { return this->listen(QHostAddress::LocalHost, 0); }
    QUrl address() const
    {
        return QUrl(QStringLiteral("http://127.0.0.1:%1").arg(this->serverPort()));
    }

protected:
    void incomingConnection(qintptr descriptor) override
    {
        QTcpSocket *socket = new QTcpSocket(this);
        if (!socket->setSocketDescriptor(descriptor))
        {
            socket->deleteLater();
            return;
        }
        QObject::connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
        QObject::connect(socket, &QTcpSocket::readyRead, socket,
            [this, socket, accumulated = QByteArray()]() mutable
        {
            accumulated.append(socket->readAll());
            const qsizetype end = accumulated.indexOf("\r\n\r\n");
            if (end < 0) return;
            const QByteArray request = accumulated.left(end + 4);
            const QByteArray path = request.split(' ').value(1);
            const bool authorized = this->expected_key.isEmpty() ||
                request.toLower().contains("x-api-key: " + this->expected_key.toLower() + "\r\n");
            const bool is_catalog = path == "/map/v1/providers/available";
            const bool is_tile = path.endsWith(".png");
            if (is_catalog) ++this->catalog_requests;
            if (is_tile) ++this->tile_requests;
            const int status = !authorized ? 403 :
                (is_catalog || (is_tile && this->tile_enabled) ? 200 : 503);
            const QByteArray payload = status != 200 ? QByteArrayLiteral("unavailable") :
                (is_catalog ? this->catalog : samplePng());
            QByteArray reply = "HTTP/1.1 " + QByteArray::number(status) +
                (status == 200 ? " OK\r\n" : " Error\r\n");
            reply += "Content-Type: " + QByteArray(is_catalog ? "application/json" : "image/png") +
                "\r\nContent-Length: " + QByteArray::number(payload.size()) + "\r\n";
            if (is_tile && !this->fingerprint.isEmpty())
                reply += "X-AOWIS-Raster-Source: " + this->fingerprint + "\r\n";
            reply += "Connection: close\r\n\r\n";
            socket->write(reply + payload);
            socket->disconnectFromHost();
        });
    }
};

bool waitForCatalog(Aowis::Map::ProviderCatalog *catalog, const QString &id)
{
    QElapsedTimer clock;
    clock.start();
    while (clock.elapsed() < 6000)
    {
        for (const Aowis::Map::AvailableMapProvider &entry : catalog->available())
            if (entry.provider.id == id && entry.inherited && entry.upstream_names.size() == 2)
                return true;
        QCoreApplication::processEvents(QEventLoop::AllEvents, 40);
        QThread::msleep(1);
    }
    return false;
}

struct TileResult
{
    QByteArray data;
    bool failed = false;
};

TileResult requestTile(MapTiles *tiles, const QString &id, int y, const QString &key)
{
    TileResult result;
    QEventLoop loop;
    QTimer watchdog;
    watchdog.setSingleShot(true);
    QObject::connect(&watchdog, &QTimer::timeout, &loop, &QEventLoop::quit);
    const QMetaObject::Connection ready = QObject::connect(
        tiles, &MapTiles::tileReady, &loop,
        [&result, &loop, &key](const QString &response_key, const QByteArray &data)
    {
        if (response_key == key)
        {
            result.data = data;
            loop.quit();
        }
    });
    const QMetaObject::Connection failed = QObject::connect(
        tiles, &MapTiles::tileFailed, &loop,
        [&result, &loop, &key](const QString &response_key, MapTiles::TileFailureReason)
    {
        if (response_key == key)
        {
            result.failed = true;
            loop.quit();
        }
    });
    const MapTiles::TileRequestResult initial = tiles->getTile(id, 6, 30, y, key);
    if (initial.status == MapTiles::TileRequestStatus::Ready)
        result.data = initial.data;
    else if (initial.status == MapTiles::TileRequestStatus::Pending)
    {
        watchdog.start(6000);
        loop.exec();
        if (result.data.isEmpty()) result.failed = true;
    }
    else result.failed = true;
    QObject::disconnect(ready);
    QObject::disconnect(failed);
    return result;
}

void configureTileRuntime(MapTiles *tiles,
                          const Aowis::Map::ProviderCatalog &catalog,
                          const Aowis::Map::MapCascadeConfig &cascade,
                          const QHash<QString, QStringList> &routes,
                          const QHash<QString, Aowis::Map::MapProviderAcquisitionMode> &modes)
{
    QVector<Aowis::Map::MapProvider> providers;
    for (const Aowis::Map::AvailableMapProvider &entry : catalog.available())
        providers.append(entry.provider);
    tiles->configureProviders(providers, {}, {}, catalog.inheritedUpstreams(), routes, modes);
    tiles->setCascadeConfig(cascade);
}
}

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    QTemporaryDir storage;
    if (!check(storage.isValid(), "create isolated Standalone storage")) return 1;
    const QString id = QString::fromLatin1(ProviderId);
    const QString cache_root = QDir(storage.path()).filePath(QStringLiteral("maptiles"));
    const QString config_root = QDir(storage.path()).filePath(QStringLiteral("config"));

    MapPeer origin;
    MapPeer first;
    MapPeer backup;
    first.expected_key = QByteArrayLiteral("primary-read");
    backup.expected_key = QByteArrayLiteral("backup-read");
    if (!check(origin.start() && first.start() && backup.start(),
               "start three independent loopback servers")) return 1;

    Aowis::Map::MapProvider advertised = Aowis::Map::defaultMapProviders().first();
    advertised.id = id;
    advertised.name = QStringLiteral("Inherited runtime test layer");
    advertised.url_template = origin.address().toString() +
        QStringLiteral("/{z}/{x}/{y}.png");
    first.catalog = Aowis::Map::encodeProviderCatalog({advertised});
    backup.catalog = first.catalog;
    const QByteArray fingerprint = QCryptographicHash::hash(
        advertised.url_template.toUtf8(), QCryptographicHash::Sha256).toHex();
    first.fingerprint = fingerprint;
    backup.fingerprint = fingerprint;

    Aowis::Map::MapCascadeConfig cascade;
    cascade.allow_direct_fetch = true; // Inherited must *still* never use origin.
    cascade.upstreams.append({QStringLiteral("primary"), first.address(), first.expected_key});
    cascade.upstreams.append({QStringLiteral("backup"), backup.address(), backup.expected_key});
    const QHash<QString, QStringList> routes{
        {id, QStringList{QStringLiteral("backup")}}};
    const QHash<QString, Aowis::Map::MapProviderAcquisitionMode> modes{
        {id, Aowis::Map::MapProviderAcquisitionMode::Cascade}};

    QString error;
    std::unique_ptr<Aowis::Map::SettingsRepository> repository =
        Aowis::Map::SettingsRepository::openAtOwnerRoot(
            QStringLiteral("standalone-map"), config_root, &error);
    if (!check(repository != nullptr && repository->saveCascade(cascade, {}, nullptr, &error) &&
               repository->saveProviderUpstreamRoutes(routes, {}, nullptr, &error) &&
               repository->saveProviderAcquisitionModes(modes, {}, nullptr, &error),
               "persist MAP routing in Standalone-owned CONFIG"))
    {
        std::fprintf(stderr, "CONFIG error: %s\n", error.toUtf8().constData());
        return 1;
    }

    {
        Aowis::Map::ProviderCatalog catalog(cache_root);
        catalog.configure({}, cascade);
        catalog.setUpstreamRoutes(routes);
        catalog.setAcquisitionModes(modes);
        catalog.refresh();
        if (!check(waitForCatalog(&catalog, id), "discover inherited layer from two MAP servers"))
            return 1;
        const Aowis::Map::AvailableMapProvider available = catalog.available().first();
        if (!check(available.selected_upstreams == QStringList{QStringLiteral("backup")} &&
                   available.acquisition_mode == Aowis::Map::MapProviderAcquisitionMode::Cascade &&
                   !available.direct_fetch_allowed,
                   "Stand-alone provider uses selected backup and forbids direct origin"))
            return 1;

        // The primary would succeed too: a backup-only route must really
        // bypass it rather than merely allowing failover to the backup.
        MapTiles tiles(cache_root, 2, 8);
        configureTileRuntime(&tiles, catalog, cascade, routes, modes);
        const TileResult delivered = requestTile(&tiles, id, 20, QStringLiteral("live"));
        if (!check(!delivered.failed && delivered.data == samplePng() &&
                   first.tile_requests == 0 && backup.tile_requests == 1 &&
                   origin.tile_requests == 0,
                   "inherited raster tile uses selected authenticated MAP peer only"))
            return 1;
        QFile cached(QDir(cache_root).filePath(
            QStringLiteral("maptiles/%1/6/30/20.png").arg(id)));
        if (!check(cached.open(QIODevice::ReadOnly) && cached.readAll() == samplePng(),
                   "inherited image is durably cached before completion")) return 1;
    }

    // All upstream MAP peers are gone. Restart from the exact same Standalone
    // CONFIG and raster directories, not from in-memory catalog state.
    first.close();
    backup.close();
    repository.reset();
    std::unique_ptr<Aowis::Map::SettingsRepository> reopened =
        Aowis::Map::SettingsRepository::openAtOwnerRoot(
            QStringLiteral("standalone-map"), config_root, &error);
    Aowis::Map::MapCascadeConfig saved_cascade;
    QHash<QString, QStringList> saved_routes;
    QHash<QString, Aowis::Map::MapProviderAcquisitionMode> saved_modes;
    if (!check(reopened != nullptr && reopened->readCascade(&saved_cascade) &&
               reopened->readProviderUpstreamRoutes(&saved_routes) &&
               reopened->readProviderAcquisitionModes(&saved_modes) &&
               saved_routes == routes && saved_modes == modes,
               "read persisted Standalone cascade policy after restart")) return 1;

    Aowis::Map::ProviderCatalog offline_catalog(cache_root);
    offline_catalog.configure({}, saved_cascade);
    offline_catalog.setUpstreamRoutes(saved_routes);
    offline_catalog.setAcquisitionModes(saved_modes);
    if (!check(waitForCatalog(&offline_catalog, id),
               "restore inherited provider definition from validated offline snapshot")) return 1;
    MapTiles offline(cache_root, 2, 8);
    configureTileRuntime(&offline, offline_catalog, saved_cascade, saved_routes, saved_modes);
    const TileResult cached = requestTile(&offline, id, 20, QStringLiteral("offline-cache"));
    if (!check(!cached.failed && cached.data == samplePng() &&
               first.tile_requests == 0 && backup.tile_requests == 1 &&
               origin.tile_requests == 0,
               "restart reuses cached inherited tile with no network traffic")) return 1;
    const TileResult missing = requestTile(&offline, id, 21, QStringLiteral("offline-miss"));
    if (!check(missing.failed && origin.tile_requests == 0,
               "offline inherited cache miss never fetches from original provider")) return 1;

    // A disabled inherited layer must not be accessible even through a warm
    // disk cache: availability control must precede cache lookup.
    offline_catalog.setDisabledInheritedProviders(QSet<QString>{id});
    MapTiles disabled(cache_root, 2, 8);
    configureTileRuntime(&disabled, offline_catalog, saved_cascade, saved_routes, saved_modes);
    if (!check(requestTile(&disabled, id, 20, QStringLiteral("disabled")).failed,
               "disabled inherited layer cannot access previously cached image")) return 1;

    std::puts("PASS: Standalone inherited raster routing, persistence and offline recovery");
    return 0;
}
