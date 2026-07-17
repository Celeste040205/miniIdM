import time
import ldap
from prometheus_client import start_http_server, Gauge

LDAP_BASE_DN = "dc=fis,dc=epn,dc=ec"
ADMIN_DN = f"cn=admin,{LDAP_BASE_DN}"
ADMIN_PW = "adminpassword"

ldap_ops_master = Gauge("ldap_ops_completed_master", "Operaciones completadas en el master")
ldap_ops_replica = Gauge("ldap_ops_completed_replica", "Operaciones completadas en la replica")
ldap_ops_per_sec = Gauge("ldap_ops_per_second", "Tasa aproximada de operaciones/seg (master)")
replication_delay = Gauge("ldap_replication_delay_seconds", "Retraso de replicacion estimado (segundos)")
node_up = Gauge("ldap_node_up", "1 si el nodo LDAP responde", ["node"])

_last_ops = {"value": None, "ts": None}


def get_conn(host):
    conn = ldap.initialize(f"ldap://{host}:389")
    conn.simple_bind_s(ADMIN_DN, ADMIN_PW)
    return conn


def get_ops_completed(host):
    conn = get_conn(host)
    res = conn.search_s(
        "cn=Total,cn=Operations,cn=Monitor", ldap.SCOPE_BASE, "(objectClass=*)", ["monitorOpCompleted"]
    )
    conn.unbind_s()
    return int(res[0][1]["monitorOpCompleted"][0])


def get_context_csn(host):
    conn = get_conn(host)
    res = conn.search_s(LDAP_BASE_DN, ldap.SCOPE_BASE, "(objectClass=*)", ["contextCSN"])
    conn.unbind_s()
    csn = res[0][1].get("contextCSN", [b""])[0].decode()
    # formato: YYYYMMDDHHMMSS.ffffffZ#...
    return csn


def csn_to_epoch(csn):
    if not csn:
        return None
    ts_str = csn.split("#")[0].split(".")[0]
    return time.mktime(time.strptime(ts_str, "%Y%m%d%H%M%S"))


def collect():
    now = time.time()
    try:
        ops_m = get_ops_completed("idm1.fis.epn.ec")
        ldap_ops_master.set(ops_m)
        node_up.labels(node="idm1").set(1)

        if _last_ops["value"] is not None:
            dt = now - _last_ops["ts"]
            if dt > 0:
                ldap_ops_per_sec.set(max(0, (ops_m - _last_ops["value"]) / dt))
        _last_ops["value"] = ops_m
        _last_ops["ts"] = now
    except Exception as e:
        node_up.labels(node="idm1").set(0)
        print("Error consultando idm1:", e)

    try:
        ops_r = get_ops_completed("idm2.fis.epn.ec")
        ldap_ops_replica.set(ops_r)
        node_up.labels(node="idm2").set(1)
    except Exception as e:
        node_up.labels(node="idm2").set(0)
        print("Error consultando idm2:", e)

    try:
        csn_master = csn_to_epoch(get_context_csn("idm1.fis.epn.ec"))
        csn_replica = csn_to_epoch(get_context_csn("idm2.fis.epn.ec"))
        if csn_master and csn_replica:
            replication_delay.set(abs(csn_master - csn_replica))
    except Exception as e:
        print("Error calculando retraso de replicacion:", e)


if __name__ == "__main__":
    start_http_server(9200)
    while True:
        collect()
        time.sleep(10)