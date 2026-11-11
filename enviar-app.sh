#!/usr/bin/env bash
# ======================================================
#  PANTHERSTREAM - ENVIAR APLICATIVO PARA O GITHUB
#  Feito para rodar no Termux (Android).
#
#  Uso:
#    bash enviar-app.sh
#    bash enviar-app.sh PantherStream-v1.3.apk
#    bash enviar-app.sh PantherStream-v1.3.apk 1.3 "Correcoes"
#
#  O script le owner/repo/asset do arquivo config.env e o token do
#  github-token.txt (ou da variavel GITHUB_TOKEN).
# ======================================================

set -u

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE_DIR" || exit 1

API="https://api.github.com"
UPLOADS="https://uploads.github.com"

falhar() {
  echo
  echo "  ERRO: $1" >&2
  echo
  exit 1
}

# ---------- configuracao ----------
OWNER="surtadosilva"
REPO="surtado"
ASSET="PantherStream.apk"
VERSAO=""
NOTAS=""
APK=""

if [ -f config.env ]; then
  # shellcheck disable=SC1091
  . ./config.env
fi

# Remove CR que pode vir de arquivos editados no Windows.
OWNER="${OWNER%$'\r'}"
REPO="${REPO%$'\r'}"
ASSET="${ASSET%$'\r'}"

# Argumentos opcionais: apk, versao, notas.
if [ "$#" -ge 1 ]; then APK="$1"; fi
if [ "$#" -ge 2 ]; then VERSAO="$2"; fi
if [ "$#" -ge 3 ]; then NOTAS="$3"; fi

# ---------- acha o APK ----------
if [ -z "$APK" ]; then
  APK="$(ls -1t PantherStream-v*.apk 2>/dev/null | head -n 1)"
fi
if [ -z "$APK" ]; then
  APK="$(ls -1t ../saida/PantherStream-v*.apk 2>/dev/null | head -n 1)"
fi
[ -n "$APK" ] || falhar "Nenhum APK encontrado. Coloque o PantherStream-vX.Y.apk nesta pasta."
[ -f "$APK" ] || falhar "APK nao encontrado: $APK"

# ---------- descobre a versao ----------
if [ -z "$VERSAO" ]; then
  VERSAO="$(basename "$APK" | sed -n 's/.*-v\([0-9][0-9.]*\)\.apk$/\1/p')"
fi
if [ -z "$VERSAO" ]; then
  VERSAO="$(basename "$APK" | sed -n 's/.*-\([0-9][0-9.]*\)\.apk$/\1/p')"
fi
if [ -z "$VERSAO" ]; then
  falhar "Nao consegui descobrir a versao. Use: bash enviar-app.sh arquivo.apk 1.3"
fi
VERSAO="${VERSAO#v}"
VERSAO="${VERSAO#V}"

if [ -z "$NOTAS" ]; then
  NOTAS="Melhorias e correcoes da versao $VERSAO."
fi

# ---------- token ----------
TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f github-token.txt ]; then
  TOKEN="$(tr -d '\r\n' < github-token.txt)"
fi
if [ -z "$TOKEN" ]; then
  printf "Token do GitHub: "
  read -r -s TOKEN
  echo
  printf '%s' "$TOKEN" > github-token.txt
fi
[ -n "$TOKEN" ] || falhar "Token vazio."

# ---------- dependencias ----------
command -v curl >/dev/null 2>&1 || falhar "Instale o curl: pkg install curl"

AUTH="Authorization: Bearer $TOKEN"
ACEITA="Accept: application/vnd.github+json"
AGENTE="User-Agent: PantherStream-Termux"
TAG="v$VERSAO"

echo ""
echo "  ======================================================"
echo "   PANTHERSTREAM - ENVIAR APLICATIVO PARA O GITHUB"
echo "  ======================================================"
echo "  Repositorio ... $OWNER/$REPO"
echo "  APK ........... $APK"
echo "  Versao ........ $VERSAO"
echo "  Asset ......... $ASSET"
echo ""

# ---------- confere a conta ----------
CONTA="$(curl -sS -H "$AUTH" -H "$ACEITA" -H "$AGENTE" "$API/user")"
case "$CONTA" in
  *suspended*)
    falhar "A conta do GitHub esta suspensa. Recorra em https://support.github.com/contact?tags=rr-suspended-account e rode de novo quando a conta voltar."
    ;;
  *'"login"'*)
    LOGIN="$(printf '%s' "$CONTA" | sed -n 's/.*"login": *"\([^"]*\)".*/\1/p' | head -n 1)"
    echo "  Conta ......... $LOGIN"
    ;;
  *)
    falhar "Token recusado pelo GitHub: $CONTA"
    ;;
esac

# ---------- remove release antiga com a mesma tag ----------
EXISTENTE="$(curl -sS -H "$AUTH" -H "$ACEITA" -H "$AGENTE" \
  "$API/repos/$OWNER/$REPO/releases/tags/$TAG")"
case "$EXISTENTE" in
  *suspended*)
    falhar "A conta do GitHub esta suspensa. Recorra em https://support.github.com/contact?tags=rr-suspended-account"
    ;;
  *'"id"'*)
    REL_ID="$(printf '%s' "$EXISTENTE" | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | head -n 1 | tr -cd '0-9')"
    if [ -n "$REL_ID" ]; then
      echo "  Release $TAG ja existe; removendo para criar de novo..."
      curl -sS -X DELETE -H "$AUTH" -H "$ACEITA" -H "$AGENTE" \
        "$API/repos/$OWNER/$REPO/releases/$REL_ID" >/dev/null
    fi
    ;;
esac

# ---------- escapa as notas para o JSON ----------
escapar_json() {
  printf '%s' "$1" | tr '\n' ' ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

CORPO="{\"tag_name\":\"$TAG\",\"name\":\"PantherStream $TAG\",\"body\":\"$(escapar_json "$NOTAS")\",\"draft\":false,\"prerelease\":false,\"make_latest\":\"true\"}"

# ---------- cria a release ----------
RESPOSTA="$(curl -sS -X POST \
  -H "$AUTH" -H "$ACEITA" -H "$AGENTE" \
  -H "Content-Type: application/json" \
  -d "$CORPO" \
  "$API/repos/$OWNER/$REPO/releases")"

case "$RESPOSTA" in
  *suspended*)
    falhar "A conta do GitHub esta suspensa. Recorra em https://support.github.com/contact?tags=rr-suspended-account"
    ;;
  *'"id"'*)
    REL_ID="$(printf '%s' "$RESPOSTA" | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | head -n 1 | tr -cd '0-9')"
    ;;
  *)
    falhar "Nao foi possivel criar a release: $RESPOSTA"
    ;;
esac

[ -n "$REL_ID" ] || falhar "Nao foi possivel obter o numero da release."

# ---------- envia o APK ----------
TAMANHO="$(wc -c < "$APK" | tr -d ' ')"
TAMANHO_MB=$((TAMANHO / 1024 / 1024))
echo "  Enviando $TAMANHO_MB MB..."

ENVIO="$(curl -sS --progress-bar -X POST \
  -H "$AUTH" -H "$ACEITA" -H "$AGENTE" \
  -H "Content-Type: application/vnd.android.package-archive" \
  --data-binary "@$APK" \
  "$UPLOADS/repos/$OWNER/$REPO/releases/$REL_ID/assets?name=$ASSET")"

case "$ENVIO" in
  *suspended*)
    falhar "A conta do GitHub esta suspensa. Recorra em https://support.github.com/contact?tags=rr-suspended-account"
    ;;
  *'"browser_download_url"'*)
    LINK="$(printf '%s' "$ENVIO" | sed -n 's/.*"browser_download_url": *"\([^"]*\)".*/\1/p' | head -n 1)"
    ;;
  *)
    falhar "Falha ao enviar o APK: $ENVIO"
    ;;
esac

echo ""
echo "  APK publicado com sucesso!"
echo "  Release ....: https://github.com/$OWNER/$REPO/releases/tag/$TAG"
[ -n "${LINK:-}" ] && echo "  Download ...: $LINK"
echo "  Link direto : https://github.com/$OWNER/$REPO/releases/latest/download/$ASSET"
echo ""
