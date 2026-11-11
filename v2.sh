#!/data/data/com.termux/files/usr/bin/bash
# ==========================================================
# ATUALIZADOR SEGURO - PROJETO + APK EM GITHUB RELEASES
# Cria uma nova versão sem apagar Releases ou forçar push.
# Execute: bash enviar_github_v2.sh
# O APK deve estar na mesma pasta deste script.
# ==========================================================

set -Eeuo pipefail

REPO_OWNER="sandrosilvaaa855-a11y"
REPO_NAME="Aplicativo"
REPO_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
BRANCH="main"
API="https://api.github.com"
BASE_DIR="$(cd "$(dirname "$0")" && pwd -P)"
cd "$BASE_DIR"
# Temporarios no armazenamento privado do Termux para evitar erro curl 23.
TMP_ROOT="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
mkdir -p "$TMP_ROOT" || exit 1
TEMP_DIR="$(mktemp -d "$TMP_ROOT/aplicativo-update.XXXXXX")" || exit 1

falhar() {
    printf '\nERRO: %s\n' "$1" >&2
    exit 1
}

pausar() {
    printf '\nPressione Enter para sair...'
    read -r _ || true
}

trap 'codigo=$?; rm -rf "$TEMP_DIR"; if [ "$codigo" -ne 0 ]; then echo; echo "O processo foi interrompido. Nenhum push forcado ou exclusao de Release e feito por este script."; fi' EXIT

echo "======================================================"
echo "        ATUALIZADOR DO APLICATIVO - V2"
echo "======================================================"
echo "Repositório: ${REPO_OWNER}/${REPO_NAME}"
echo "Pasta: $BASE_DIR"
echo

# Dependências
for programa in git curl jq; do
    command -v "$programa" >/dev/null 2>&1 ||
        falhar "Falta o programa '$programa'. Instale com: pkg install git curl jq -y"
done

[ -n "${BASH_VERSION:-}" ] || falhar "Execute com Bash: bash enviar_github_v2.sh"

# Encontrar APKs somente na mesma pasta do script.
mapfile -d '' APK_LIST < <(find "$BASE_DIR" -maxdepth 1 -type f -iname '*.apk' -print0 | sort -z)

[ "${#APK_LIST[@]}" -gt 0 ] || falhar "Nenhum APK foi encontrado na mesma pasta deste script."

echo "APKs encontrados:"
echo "------------------------------------------------------"
for i in "${!APK_LIST[@]}"; do
    arquivo="${APK_LIST[$i]}"
    tamanho="$(du -h "$arquivo" | awk '{print $1}')"
    printf "%2d) %s  (%s)\n" "$((i + 1))" "$(basename "$arquivo")" "$tamanho"
done
echo "------------------------------------------------------"

while true; do
    printf "Digite o número do APK que deseja publicar: "
    read -r escolha
    if [[ "$escolha" =~ ^[0-9]+$ ]] &&
       [ "$escolha" -ge 1 ] &&
       [ "$escolha" -le "${#APK_LIST[@]}" ]; then
        break
    fi
    echo "Opção inválida. Escolha um número da lista."
done

APK="${APK_LIST[$((escolha - 1))]}"
APK_NAME="$(basename "$APK")"

# Token: variável de ambiente, arquivo local ou GitHub CLI.
TOKEN="${GITHUB_TOKEN:-}"
TOKEN_FILE="$BASE_DIR/github-token.txt"

if [ -z "$TOKEN" ] && [ -f "$TOKEN_FILE" ]; then
    TOKEN="$(tr -d '\r\n' < "$TOKEN_FILE")"
fi

if [ -z "$TOKEN" ] && command -v gh >/dev/null 2>&1; then
    TOKEN="$(gh auth token 2>/dev/null || true)"
fi

if [ -z "$TOKEN" ]; then
    printf "Cole seu token do GitHub (ele não será exibido): "
    IFS= read -r -s TOKEN
    echo
    [ -n "$TOKEN" ] || falhar "Token vazio."
    umask 077
    printf '%s' "$TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    echo "Token salvo localmente em github-token.txt (não compartilhe esse arquivo)."
fi

AUTH_HEADER="Authorization: Bearer $TOKEN"
ACCEPT_HEADER="Accept: application/vnd.github+json"
USER_AGENT="Aplicativo-Termux-Updater"

# Validar token e acesso ao repositório.
echo
echo "Verificando autenticação e acesso ao GitHub..."
HTTP_CODE="$(curl -sS -o "$TEMP_DIR/user_check.json" -w '%{http_code}' \
    -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "User-Agent: $USER_AGENT" \
    "$API/user")"
[ "$HTTP_CODE" = "200" ] || falhar "Token recusado ou sem acesso (HTTP $HTTP_CODE). Confira o token e as permissões."

LOGIN="$(jq -r '.login // "desconhecido"' "$TEMP_DIR/user_check.json")"
echo "Conta autenticada: $LOGIN"

# Identificar versão automaticamente pelo nome, se possível.
VERSAO_SUGERIDA="$(printf '%s' "$APK_NAME" | sed -nE 's/.*[vV]([0-9]+(\.[0-9]+){1,2}).*\.apk$/\1/p')"
echo
if [ -n "$VERSAO_SUGERIDA" ]; then
    printf "Versão do APK detectada: %s\n" "$VERSAO_SUGERIDA"
    printf "Use essa versão ou digite outra: "
else
    printf "Digite a versão (exemplo 1.0.3): "
fi
read -r VERSAO
[ -n "$VERSAO" ] || VERSAO="$VERSAO_SUGERIDA"

[[ "$VERSAO" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    falhar "Versão inválida. Use o formato X.Y.Z, por exemplo 1.0.3."

TAG="v$VERSAO"

printf "Mensagem da atualização: "
read -r MENSAGEM
[ -n "$MENSAGEM" ] || falhar "A mensagem não pode ficar vazia."

# Não apagar nem substituir Releases existentes.
echo
echo "Conferindo se a versão já foi utilizada..."
RELEASE_HTTP="$(curl -sS -o "$TEMP_DIR/release_check.json" -w '%{http_code}' \
    -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "User-Agent: $USER_AGENT" \
    "$API/repos/$REPO_OWNER/$REPO_NAME/releases/tags/$TAG")"
[ "$RELEASE_HTTP" = "404" ] ||
    falhar "A Release $TAG já existe ou não foi possível consultar (HTTP $RELEASE_HTTP). Nada será apagado. Escolha outra versão."

# Preparar Git sem apagar arquivos ou histórico.
git config --global --add safe.directory "$BASE_DIR"

if [ ! -d .git ]; then
    echo "Inicializando Git nesta pasta..."
    git init
fi

git branch -M "$BRANCH"

if git remote get-url origin >/dev/null 2>&1; then
    REMOTE="$(git remote get-url origin)"
    [ "$REMOTE" = "$REPO_URL" ] ||
        falhar "O remoto origin aponta para '$REMOTE', não para '$REPO_URL'. Não alterei o remoto."
else
    git remote add origin "$REPO_URL"
fi

git config user.name >/dev/null 2>&1 || git config user.name "Atualizador Aplicativo"
git config user.email >/dev/null 2>&1 || git config user.email "atualizador@users.noreply.github.com"

# Atualizar os arquivos de versão como o script original fazia.
printf '%s\n' "$VERSAO" > VERSAO.txt
touch README.md
if grep -q '^Versão atual:' README.md; then
    sed -i "s/^Versão atual:.*/Versão atual: $VERSAO/" README.md
else
    printf '\nVersão atual: %s\n' "$VERSAO" >> README.md
fi

{
    printf '\n## Versão %s\n\n' "$VERSAO"
    printf '%s\n' "- Data: $(date '+%d/%m/%Y %H:%M')"
    printf '%s\n' "- Atualização: $MENSAGEM"
} >> CHANGELOG.md

# Criar manifesto JSON de atualizacao para o aplicativo.
API_URL="$API/repos/$REPO_OWNER/$REPO_NAME/releases/latest"
RELEASE_URL_PREVISTA="https://github.com/$REPO_OWNER/$REPO_NAME/releases/tag/$TAG"
APK_URL_PREVISTA="https://github.com/$REPO_OWNER/$REPO_NAME/releases/download/$TAG/$(jq -rn --arg n "$APK_NAME" '$n|@uri')"
jq -n --arg app "$REPO_NAME" --arg version "$VERSAO" --arg tag "$TAG" \
  --arg message "$MENSAGEM" --arg apk "$APK_NAME" --arg api "$API_URL" \
  --arg release "$RELEASE_URL_PREVISTA" --arg download "$APK_URL_PREVISTA" \
  --arg date "$(date -Iseconds)" \
  '{aplicativo:$app, versao:$version, tag:$tag, mensagem:$message, arquivo_apk:$apk, api_ultima_versao:$api, pagina_release:$release, download_apk:$download, publicado_em:$date}' > update.json

# Proteger arquivos locais e credenciais contra inclusao no commit.
touch .gitignore
for regra in "github-token.txt" "config.env" ".env" ".env.*" "*.pem" "*.key" "*.p12" "*.keystore" "*.jks" "*.apk"; do
    grep -Fqx "$regra" .gitignore || printf '%s\n' "$regra" >> .gitignore
done
if git ls-files --error-unmatch github-token.txt >/dev/null 2>&1; then
    falhar "github-token.txt ja esta rastreado pelo Git. O arquivo local foi preservado. Remova-o do controle de versao com git rm --cached github-token.txt e revise o historico antes de continuar."
fi

# Adicionar arquivos do projeto, mas nunca incluir APK, token ou configuracao local.
git add -A
git reset -q -- "$APK_NAME" "github-token.txt" "config.env" "LINKS_ATUALIZACAO.txt" 2>/dev/null || true

if git diff --cached --quiet; then
    falhar "Nenhuma alteração do projeto para enviar. O APK escolhido não foi adicionado ao Git."
fi

echo
echo "======================================================"
echo "RESUMO ANTES DO ENVIO"
echo "======================================================"
echo "Projeto: $REPO_OWNER/$REPO_NAME"
echo "Branch: $BRANCH"
echo "APK: $APK_NAME"
echo "Versão: $VERSAO"
echo "Mensagem: $MENSAGEM"
echo
git status --short
echo "======================================================"
printf "Confirma o envio do projeto e a publicação do APK? (s/n): "
read -r CONFIRMA
case "$CONFIRMA" in
    s|S) ;;
    *) echo "Cancelado. Nenhum push foi feito."; exit 0 ;;
esac

# Autenticação Git sem gravar token na URL do remoto.
AUTH_B64="$(printf 'x-access-token:%s' "$TOKEN" | base64 | tr -d '\r\n')"
git_auth() {
    git -c "http.extraheader=AUTHORIZATION: basic $AUTH_B64" "$@"
}

git commit -m "Versão $VERSAO - $MENSAGEM"

echo
echo "Buscando alterações do GitHub..."
git_auth fetch origin

if git_auth ls-remote --heads origin "$BRANCH" | grep -q "refs/heads/$BRANCH"; then
    if ! git merge --no-edit --allow-unrelated-histories "origin/$BRANCH"; then
        falhar "Foi encontrado um conflito de merge. Resolva-o manualmente; nada foi sobrescrito à força."
    fi
fi

# Verificar tag local e remota antes de criar.
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    falhar "A tag local $TAG já existe. Nenhuma tag será substituída."
fi
if git_auth ls-remote --tags origin "refs/tags/$TAG" | grep -q "refs/tags/$TAG"; then
    falhar "A tag remota $TAG já existe. Nenhuma tag será substituída."
fi

git tag -a "$TAG" -m "Versão $VERSAO"

echo
echo "Enviando o projeto para a branch $BRANCH..."
git_auth push -u origin "$BRANCH" ||
    falhar "Falha ao enviar a branch. O commit permanece salvo localmente."

echo "Enviando a tag $TAG..."
git_auth push origin "$TAG" ||
    falhar "O projeto foi enviado, mas a tag não. A tag local foi preservada."

echo
echo "Projeto enviado. Aguardando 20 segundos antes de publicar o APK..."
for segundos in 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1; do
    printf '\rAguarde: %02d segundos ' "$segundos"
    sleep 1
done
printf '\rContinuando...                    \n'

# Criar Release usando a tag enviada. Nunca excluir Releases antigas.
PAYLOAD="$(jq -n \
    --arg tag "$TAG" \
    --arg nome "Aplicativo $TAG" \
    --arg notas "$MENSAGEM" \
    '{tag_name:$tag, name:$nome, body:$notas, draft:false, prerelease:false, make_latest:"true"}')"

RELEASE_RESPONSE="$(curl -sS -X POST \
    -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" \
    -H "User-Agent: $USER_AGENT" -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$API/repos/$REPO_OWNER/$REPO_NAME/releases")"

REL_ID="$(printf '%s' "$RELEASE_RESPONSE" | jq -r '.id // empty')"
UPLOAD_URL="$(printf '%s' "$RELEASE_RESPONSE" | jq -r '.upload_url // empty' | sed 's/{.*$//')"
RELEASE_URL="$(printf '%s' "$RELEASE_RESPONSE" | jq -r '.html_url // empty')"

[ -n "$REL_ID" ] && [ -n "$UPLOAD_URL" ] ||
    falhar "O projeto e a tag foram enviados, mas a criação da Release falhou: $(printf '%s' "$RELEASE_RESPONSE" | jq -r '.message // "resposta inválida"')"

echo "Release criada. Enviando APK..."
ASSET_ENCODED="$(jq -rn --arg nome "$APK_NAME" '$nome|@uri')"
UPLOAD_RESPONSE="$(curl -fSs --progress-bar -X POST \
    -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" \
    -H "User-Agent: $USER_AGENT" \
    -H "Content-Type: application/vnd.android.package-archive" \
    --data-binary "@$APK" \
    "$UPLOAD_URL?name=$ASSET_ENCODED")" ||
    falhar "A Release foi criada, mas o upload do APK falhou. A Release e a tag foram preservadas."

DOWNLOAD_URL="$(printf '%s' "$UPLOAD_RESPONSE" | jq -r '.browser_download_url // empty')"
[ -n "$DOWNLOAD_URL" ] || falhar "O upload terminou, mas não consegui obter o link do APK."

RELEASE_URL="${RELEASE_URL:-https://github.com/$REPO_OWNER/$REPO_NAME/releases/tag/$TAG}"
API_URL="$API/repos/$REPO_OWNER/$REPO_NAME/releases/latest"
jq --arg download "$DOWNLOAD_URL" --arg release "$RELEASE_URL" \
  '.download_apk=$download | .pagina_release=$release' update.json > "$TEMP_DIR/update.json"
mv "$TEMP_DIR/update.json" update.json
JSON_RESPONSE="$(curl -fSs --progress-bar -X POST \
  -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "User-Agent: $USER_AGENT" \
  -H "Content-Type: application/json" --data-binary '@update.json' \
  "$UPLOAD_URL?name=update.json")" || falhar "APK publicado, mas falhou o envio do JSON. A Release foi preservada."
JSON_DOWNLOAD_URL="$(printf '%s' "$JSON_RESPONSE" | jq -r '.browser_download_url // empty')"
[ -n "$JSON_DOWNLOAD_URL" ] || falhar "Nao foi possivel obter o link do JSON."
LATEST_DOWNLOAD="https://github.com/$REPO_OWNER/$REPO_NAME/releases/latest/download/$ASSET_ENCODED"

{
    echo "Aplicativo - Links de atualização"
    echo "Versão: $VERSAO"
    echo "Tag: $TAG"
    echo "Release: $RELEASE_URL"
    echo "API de atualização: $API_URL"
    echo "JSON da Release: $JSON_DOWNLOAD_URL"
    echo "Download do APK desta versão: $DOWNLOAD_URL"
    echo "Download da versão mais recente: $LATEST_DOWNLOAD"
} > LINKS_ATUALIZACAO.txt

echo
echo "======================================================"
echo "          PUBLICAÇÃO CONCLUÍDA!"
echo "======================================================"
echo "Projeto: $REPO_URL"
echo "Versão: $VERSAO"
echo "Release: $RELEASE_URL"
echo "API de atualização: $API_URL"
echo "JSON: $JSON_DOWNLOAD_URL"
echo "Download do APK: $DOWNLOAD_URL"
echo "Links salvos em: $BASE_DIR/LINKS_ATUALIZACAO.txt"
echo "======================================================"
echo "Observação: Releases antigas e histórico do Git não foram apagados."
