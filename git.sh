#!/data/data/com.termux/files/usr/bin/bash

# ==========================================
# ATUALIZADOR DO APLICATIVO - GITHUB + RELEASE
# ==========================================

set -Eeuo pipefail

REPO_URL="https://github.com/sandrosilvaaa855-a11y/Aplicativo.git"
REPO_SLUG="sandrosilvaaa855-a11y/Aplicativo"
BRANCH="main"
API_LATEST="https://api.github.com/repos/${REPO_SLUG}/releases/latest"

erro() {
    printf '\nERRO: %s\n' "$1" >&2
    exit 1
}

aviso() {
    printf '\nAVISO: %s\n' "$1"
}

echo "======================================"
echo "       ATUALIZADOR DO APLICATIVO"
echo "======================================"

# Verificar ferramentas necessárias
command -v git >/dev/null 2>&1 || erro "Git não está instalado. Execute: pkg install git -y"
command -v gh  >/dev/null 2>&1 || erro "GitHub CLI não está instalado. Execute: pkg install gh -y"

if [[ -z "${BASH_VERSION:-}" ]]; then
    erro "Execute este arquivo com Bash: bash teste.sh"
fi

DIR="$(pwd -P)"
git config --global --add safe.directory "$DIR" 2>/dev/null || true

# Confirmar autenticação antes de alterar o projeto
if ! gh auth status >/dev/null 2>&1; then
    echo ""
    echo "Você ainda não está conectado ao GitHub."
    echo "Execute: gh auth login"
    erro "Faça a autenticação e execute o script novamente."
fi

# Inicializar repositório, se necessário
if [[ ! -d ".git" ]]; then
    echo "Inicializando repositório..."
    git init -b "$BRANCH"
fi

git branch -M "$BRANCH"

# Configurar/verificar remoto
if git remote get-url origin >/dev/null 2>&1; then
    REMOTE="$(git remote get-url origin)"
    case "$REMOTE" in
        "$REPO_URL"|"https://github.com/${REPO_SLUG}"|"git@github.com:${REPO_SLUG}.git")
            ;;
        *)
            erro "O remoto origin aponta para outro repositório: $REMOTE"
            ;;
    esac
else
    git remote add origin "$REPO_URL"
fi

# Configurar identidade Git, caso ainda não exista
if ! git config user.name >/dev/null 2>&1; then
    git config user.name "Atualizador Aplicativo"
fi

if ! git config user.email >/dev/null 2>&1; then
    git config user.email "atualizador@users.noreply.github.com"
fi

# Solicitar versão
echo ""
echo "======================================"
echo "       NOVA VERSÃO DO APLICATIVO"
echo "======================================"

while true; do
    printf "Digite a versão (ex: 1.0.0): "
    IFS= read -r VERSAO

    if [[ "$VERSAO" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
    fi

    echo "Versão inválida! Use o formato 1.0.0."
done

TAG="v${VERSAO}"

# Verificar se a tag já existe localmente ou no GitHub
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
    erro "A tag ${TAG} já existe neste computador."
fi

if git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
    erro "A tag ${TAG} já existe no GitHub."
fi

# Solicitar descrição
echo ""
printf "Digite a mensagem da atualização: "
IFS= read -r MENSAGEM

[[ -n "${MENSAGEM//[[:space:]]/}" ]] || erro "A mensagem da atualização não pode ficar vazia."

# Atualizar arquivos de versão
printf '%s\n' "$VERSAO" > VERSAO.txt
touch README.md CHANGELOG.md

if grep -q '^Versão atual:' README.md; then
    sed -i "s/^Versão atual:.*/Versão atual: ${VERSAO}/" README.md
else
    printf '\nVersão atual: %s\n' "$VERSAO" >> README.md
fi

{
    printf '\n## Versão %s\n\n' "$VERSAO"
    printf '%s\n' "- Data: $(date '+%d/%m/%Y %H:%M')"
    printf '%s\n' "- Atualização: $MENSAGEM"
} >> CHANGELOG.md

# Mostrar resumo
echo ""
echo "======================================"
echo "       RESUMO DA ATUALIZAÇÃO"
echo "======================================"
echo "Repositório: $REPO_SLUG"
echo "Versão: $VERSAO"
echo "Mensagem: $MENSAGEM"
echo "======================================"

# Adicionar arquivos
git add -A

if git diff --cached --quiet; then
    erro "Nenhuma alteração encontrada para enviar."
fi

echo ""
git status --short

printf '\nDeseja enviar ao GitHub e criar a Release? (s/n): '
IFS= read -r CONFIRMA

case "$CONFIRMA" in
    s|S)
        ;;
    *)
        echo "Envio cancelado. Desfazendo apenas o stage dos arquivos..."
        git reset
        exit 0
        ;;
esac

# Commit
git commit -m "Versão ${VERSAO} - ${MENSAGEM}"

# Buscar alterações remotas e integrar histórico
echo ""
echo "Verificando alterações no GitHub..."
git fetch origin

if git ls-remote --heads origin "$BRANCH" | grep -q "refs/heads/${BRANCH}"; then
    if ! git merge --no-edit --allow-unrelated-histories "origin/${BRANCH}"; then
        erro "Conflito ao integrar o histórico remoto. Resolva os conflitos e execute novamente."
    fi
fi

# Criar tag da versão
git tag -a "$TAG" -m "Versão ${VERSAO}"

# Enviar branch e tag
echo ""
echo "Enviando projeto para o GitHub..."
git push -u origin "$BRANCH" || erro "Falha ao enviar a branch. O commit continua salvo localmente."

echo "Enviando tag ${TAG}..."
git push origin "$TAG" || erro "A branch foi enviada, mas houve falha ao enviar a tag."

# Criar Release no GitHub usando a tag enviada
echo ""
echo "Criando Release no GitHub..."
if gh release create "$TAG" \
    --repo "$REPO_SLUG" \
    --title "Versão ${VERSAO}" \
    --notes "$MENSAGEM" \
    --verify-tag; then
    echo "Release criada com sucesso."
else
    aviso "Não foi possível criar a Release automaticamente."
    aviso "Confira as permissões da conta e se a tag ${TAG} foi enviada."
    echo "Você pode tentar novamente com:"
    echo "gh release create ${TAG} --repo ${REPO_SLUG} --title 'Versão ${VERSAO}' --notes '${MENSAGEM}' --verify-tag"
    exit 1
fi

# Resultado
echo ""
echo "======================================"
echo "       ATUALIZAÇÃO CONCLUÍDA!"
echo "======================================"
echo "Aplicativo: Aplicativo"
echo "Versão: $VERSAO"
echo "Tag: $TAG"
echo "Mensagem: $MENSAGEM"
echo ""
echo "Página da Release:"
echo "https://github.com/${REPO_SLUG}/releases/latest"
echo ""
echo "LINK DA API PARA O APLICATIVO:"
echo "$API_LATEST"
echo "======================================"
