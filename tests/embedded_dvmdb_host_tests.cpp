#include "projects/embedded_dvmdb_host.h"
#include "projects/dvmdb_identity.h"

#include <httplib.h>

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
#include <QUrl>

#include <iostream>
#include <memory>

namespace
{
bool check(bool valid, const char *message)
{
    if (!valid) std::cerr << "standalone_embedded_dvmdb: " << message << '\n';
    return valid;
}

QJsonObject get(httplib::Client &client, const QString &path, int expected)
{
    const httplib::Result response = client.Get(path.toStdString());
    if (!response || response->status != expected)
        return {};
    return QJsonDocument::fromJson(QByteArray::fromStdString(response->body)).object();
}

QJsonObject post(httplib::Client &client, const QString &path,
                 const QJsonObject &request, int expected)
{
    const QByteArray encoded = QJsonDocument(request).toJson(QJsonDocument::Compact);
    const httplib::Result response = client.Post(path.toStdString(),
        std::string(encoded.constData(), static_cast<std::size_t>(encoded.size())),
        "application/json");
    if (!response || response->status != expected)
        return {};
    return QJsonDocument::fromJson(QByteArray::fromStdString(response->body)).object();
}
}

int main()
{
#ifndef AOWIS_STANDALONE_DVMDB_ENABLED
    std::cerr << "standalone_embedded_dvmdb: embedded support disabled\n";
    return 1;
#else
    QTemporaryDir root;
    if (!check(root.isValid(), "temporary storage directory unavailable")) return 1;
    QString error;
    QString repository_id;
    const QString endpoint = embeddedDvmdbEndpoint(root.path(), false, &repository_id, &error);
    if (!check(error.isEmpty() && endpoint.startsWith(QStringLiteral("http://127.0.0.1:"))
               && DvmdbIdentity::isUuidV7(repository_id),
               "local server did not start on process-owned loopback")) return 1;
    const QUrl address(endpoint);
    httplib::Client client("127.0.0.1", address.port());
    client.set_connection_timeout(2, 0);
    const QString prefix = QStringLiteral("/dvmdb/v1");
    QJsonObject tracking = get(client, prefix + QStringLiteral("/repository/tracking"), 200);
    if (!check(tracking.value(QStringLiteral("repositoryId")).toString() == repository_id &&
               tracking.value(QStringLiteral("role")).toString() == QStringLiteral("unconfigured"),
               "local repository identity or default role incorrect")) return 1;
    QString private_id;
    const QString selected_endpoint = embeddedDvmdbEndpoint(root.path(), true, &private_id, &error);
    if (!check(error.isEmpty() && endpoint == selected_endpoint && private_id == repository_id,
               "personal selection did not reuse the same catalogue owner")) return 1;
    tracking = get(client, prefix + QStringLiteral("/repository/tracking"), 200);
    if (!check(tracking.value(QStringLiteral("role")).toString() == QStringLiteral("private"),
               "personal repository role was not persisted")) return 1;

    const QString project_id = DvmdbIdentity::newUuidV7();
    const QJsonObject created = post(client, prefix + QStringLiteral("/projects"),
        {{QStringLiteral("id"), project_id},
         {QStringLiteral("name"), QStringLiteral("Standalone smoke")},
         {QStringLiteral("unborn"), true}}, 201);
    if (!check(created.value(QStringLiteral("id")).toString() == project_id,
               "project creation through embedded routes failed")) return 1;
    const QJsonObject graph = get(client, prefix + QStringLiteral("/projects/") + project_id
        + QStringLiteral("/revision-graph"), 200);
    const QJsonArray heads = graph.value(QStringLiteral("heads")).toArray();
    if (!check(heads.size() == 1, "new project must have a single unborn branch")) return 1;
    const QString branch_id = heads.first().toObject().value(QStringLiteral("branchId")).toString();
    if (!check(DvmdbIdentity::isUuidV7(branch_id), "new branch UUID is invalid")) return 1;
    const QString draft_id = DvmdbIdentity::newUuidV7();
    const QString session_id = DvmdbIdentity::newUuidV7();
    const QJsonObject draft = post(client, prefix + QStringLiteral("/working-copies"),
        {{QStringLiteral("id"), draft_id},
         {QStringLiteral("projectId"), project_id},
         {QStringLiteral("branchId"), branch_id},
         {QStringLiteral("baseRevision"), QJsonValue(QJsonValue::Null)},
         {QStringLiteral("sessionId"), session_id}}, 201);
    if (!check(draft.value(QStringLiteral("id")).toString() == draft_id &&
               draft.value(QStringLiteral("baseRevision")).isNull(),
               "embedded unborn working-copy creation failed")) return 1;
    const QJsonObject reopened = get(client, prefix + QStringLiteral("/working-copies/")
        + draft_id, 200);
    if (!check(reopened.value(QStringLiteral("id")).toString() == draft_id &&
               reopened.value(QStringLiteral("generation")).toString() == QStringLiteral("0"),
               "embedded working-copy reopen failed")) return 1;
    const QString draft_path = prefix + QStringLiteral("/working-copies/") + draft_id;
    const QJsonObject lease = post(client, draft_path + QStringLiteral("/lease"),
        {{QStringLiteral("sessionId"), session_id}, {QStringLiteral("seconds"), 90}}, 200);
    const QString token = lease.value(QStringLiteral("token")).toString();
    if (!check(DvmdbIdentity::isUuidV7(token) &&
               lease.value(QStringLiteral("generation")).toString() == QStringLiteral("0"),
               "embedded writer lease acquisition failed")) return 1;
    const QString network_id = DvmdbIdentity::newUuidV7();
    const QJsonObject initialized = post(client,
        draft_path + QStringLiteral("/initialize-network"),
        {{QStringLiteral("sessionId"), session_id},
         {QStringLiteral("fencingToken"), token},
         {QStringLiteral("expectedGeneration"), QStringLiteral("0")},
         {QStringLiteral("networkId"), network_id},
         {QStringLiteral("name"), QStringLiteral("Embedded network")}}, 200);
    if (!check(initialized.value(QStringLiteral("generation")).toString() == QStringLiteral("1"),
               "embedded first-network initialization failed")) return 1;
    const QJsonObject network = get(client, draft_path + QStringLiteral("/networks/")
        + network_id, 200);
    if (!check(network.value(QStringLiteral("networkId")).toString() == network_id &&
               network.value(QStringLiteral("generation")).toString() == QStringLiteral("1") &&
               !network.value(QStringLiteral("payloadBase64")).toString().isEmpty(),
               "embedded hydraulic network hydration failed")) return 1;
    return 0;
#endif
}
