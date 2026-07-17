import base64
import os
import ssl

import gssapi
from flask import Flask, Response, request

app = Flask(__name__)

REALM = os.environ.get("REALM", "FIS.EPN.EC")
CERT_FILE = os.environ.get("TLS_CERT", "/etc/fis-ca/webserver.crt")
KEY_FILE = os.environ.get("TLS_KEY", "/etc/fis-ca/webserver.key")


def negotiate_auth():
    """Realiza el handshake SPNEGO/GSSAPI. Devuelve el nombre del cliente
    autenticado o None si falla / falta el header."""
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Negotiate "):
        return None, None

    token = base64.b64decode(auth_header.split(" ", 1)[1])
    server_name = gssapi.Name(
        f"HTTP@webserver.fis.epn.ec", gssapi.NameType.hostbased_service
    )
    server_creds = gssapi.Credentials(name=server_name, usage="accept")
    ctx = gssapi.SecurityContext(creds=server_creds, usage="accept")
    out_token = ctx.step(token)

    if ctx.complete:
        client_name = str(ctx.initiator_name)
        resp_token = base64.b64encode(out_token).decode() if out_token else ""
        return client_name, resp_token
    return None, None


@app.route("/")
def index():
    client_name, resp_token = negotiate_auth()

    if client_name is None:
        resp = Response("Autenticacion Kerberos requerida", 401)
        resp.headers["WWW-Authenticate"] = "Negotiate"
        return resp

    headers = {}
    if resp_token:
        headers["WWW-Authenticate"] = f"Negotiate {resp_token}"

    body = (
        f"<h1>FIS - Servicio Web Protegido</h1>"
        f"<p>Autenticado correctamente vía Kerberos como: <b>{client_name}</b></p>"
        f"<p>Realm: {REALM}</p>"
        f"<p>Conexion cifrada con certificado emitido por la CA FIS.</p>"
    )
    return Response(body, 200, headers=headers)


if __name__ == "__main__":
    ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_context.load_cert_chain(certfile=CERT_FILE, keyfile=KEY_FILE)
    app.run(host="0.0.0.0", port=8443, ssl_context=ssl_context)