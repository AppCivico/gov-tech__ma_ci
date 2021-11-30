#!/bin/bash
set -e

BUILD_TS=$(date '+%F-%Hh%Mm%Ss')

HOME="/home/$USER"

EE_CURRENT_VERSION="ee.6.0.6.patched-v2.tar.gz"

# diretorio com o source deste proprio deploy.sh!
GOV_MA_CI_GIT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

set -x

# diretorio com o source code para a nova versao
GOV_MA_GIT_SRC_DIR="${GOV_MA_GIT_SRC_DIR:-$HOME/gov_ma_git}"

# diretorio onde existe o link simbólico para a versao corrente, e onde serao criados as novas versoes
GOV_MA_SERVER_BASE_DIR="${GOV_MA_SERVER_BASE_DIR:-$HOME/gov_ma_server}"

# diretorio com os uploads que sempre são os mesmos entre todas as versoes do site
GOV_MA_UPLOAD_DIR="${GOV_MA_UPLOAD_DIR:-$HOME/gov_ma_uploads}"

# diretorio com os uploads (privados, avatar dos administradores) que sempre são os mesmos entre todas as versoes do site
GOV_MA_IMAGE_DIR="${GOV_MA_IMAGE_DIR:-$HOME/gov_ma_private_uploads}"

# diretorio com a pasta node_modules pra agilizar o build
NODE_MODULES_CACHE_DIR="${NODE_MODULES_CACHE_DIR:-$HOME/gov_ma_node_modules}"

# arquivo de configuração do EE com ENVS que podem trocar durante o runtime sem downtime
# (eg: email, banco(?!!?!), etc)
GOV_MA_USER_ENV_FILE="${GOV_MA_USER_ENV_FILE:-$HOME/gov_ma_user_envfile}"

[ ! -d "$GOV_MA_SERVER_BASE_DIR" ] && echo "GOV_MA_SERVER_BASE_DIR [$GOV_MA_SERVER_BASE_DIR] não existe. Configurare o diretorio base (este diretorio precisa ser montado no container do apache)" && exit
[ ! -d "$GOV_MA_UPLOAD_DIR" ] && echo "GOV_MA_UPLOAD_DIR [$GOV_MA_UPLOAD_DIR] não existe. Diretorio de upload persistente precisa existir!" && exit
[ ! -d "$GOV_MA_IMAGE_DIR" ] && echo "GOV_MA_IMAGE_DIR [$GOV_MA_IMAGE_DIR] não existe. Diretorio de upload privado persistente precisa existir!" && exit
[ ! -d "$GOV_MA_CI_GIT" ] && echo "GOV_MA_CI_GIT [$GOV_MA_CI_GIT] não existe ou não está configurado corretamente" && exit


# testando se os arquivos do CI existem
[ ! -f "$GOV_MA_CI_GIT/deploy.sh" ] && echo "[$GOV_MA_CI_GIT/deploy.sh] não existe!" && exit
[ ! -d "$GOV_MA_CI_GIT/vendor" ] && echo "[$GOV_MA_CI_GIT/vendor] não existe!" && exit
[ ! -f "$GOV_MA_CI_GIT/vendor/$EE_CURRENT_VERSION" ] && echo "[$GOV_MA_CI_GIT/vendor/$EE_CURRENT_VERSION] não existe!" && exit
[ ! -f "$GOV_MA_CI_GIT/vendor/themes.tar.gz" ] && echo "[$GOV_MA_CI_GIT/vendor/themes.tar.gz] não existe!" && exit
[ ! -f "$GOV_MA_USER_ENV_FILE" ] && echo "GOV_MA_USER_ENV_FILE [$GOV_MA_USER_ENV_FILE] não existe! Abortando..." && exit

[ ! -d "$NODE_MODULES_CACHE_DIR" ] && mkdir -p $NODE_MODULES_CACHE_DIR && chown 1000:1000 $NODE_MODULES_CACHE_DIR


GOV_MA_WORK_DIR=""

# https://www.spinics.net/lists/git/msg142043.html
require_clean_work_tree () {
    # Update the index
    git update-index -q --ignore-submodules --refresh
    err=0

    # Disallow unstaged changes in the working tree
    if ! git diff-files --quiet --ignore-submodules --
    then
        echo >&2 "cannot $1: you have unstaged changes."
        git diff-files --name-status -r --ignore-submodules -- >&2
        err=1
    fi

    # Disallow uncommitted changes in the index
    if ! git diff-index --cached --quiet HEAD --ignore-submodules --
    then
        echo >&2 "cannot $1: your index contains uncommitted changes."
        git diff-index --cached --name-status -r --ignore-submodules HEAD -- >&2
        err=1
    fi

    CH=$(git ls-files -o --directory --exclude-standard | sed q | wc -l)
    # Disallow uncommitted diff
    if (( $CH > 0 ))
    then
        echo >&2 "cannot $1: git contains untracked files:"
        git status
        err=1
    fi

    if [ $err = 1 ]
    then
        echo >&2 "Please commit or stash them."
        exit 1
    fi
}

prepare_source_dir() {

    # conferindo se o diretorio existe
    [ ! -d "$GOV_MA_GIT_SRC_DIR" ] && echo "GOV_MA_GIT_SRC_DIR [$GOV_MA_GIT_SRC_DIR] não existe!" && exit

    # conferindo se o source (git) esta com os arquivos esperados
    [ ! -d "$GOV_MA_GIT_SRC_DIR/data" ] && echo "$GOV_MA_GIT_SRC_DIR/data não existe" && exit
    [ ! -d "$GOV_MA_GIT_SRC_DIR/data/system" ] && echo "$GOV_MA_GIT_SRC_DIR/data/system não existe" && exit
    [ ! -d "$GOV_MA_GIT_SRC_DIR/data/system/user" ] && echo "$GOV_MA_GIT_SRC_DIR/data/system/user não existe" && exit
    [ ! -d "$GOV_MA_GIT_SRC_DIR/data/html" ] && echo "$GOV_MA_GIT_SRC_DIR/data/html não existe" && exit

    cd $GOV_MA_GIT_SRC_DIR
    echo "git $GOV_MA_GIT_SRC_DIR: verificando se está sem mudanças sem commitar"
    require_clean_work_tree
    echo "git $GOV_MA_GIT_SRC_DIR: puxando alterações"
    git pull origin main

}

prepare_build_dir (){
    GOV_MA_WORK_DIR="${GOV_MA_WORK_DIR:-$HOME/gov_ma_tmp_build}"

    [ -d "$GOV_MA_WORK_DIR" ] && echo "build: apagando $GOV_MA_WORK_DIR. build anterior incompleto?" && rm -rf $GOV_MA_WORK_DIR

    echo "build: Criando diretorio para build GOV_MA_WORK_DIR [$GOV_MA_WORK_DIR]" && mkdir -p $GOV_MA_WORK_DIR

    echo "build: Clonando $GOV_MA_GIT_SRC_DIR/ para $GOV_MA_WORK_DIR/"

    rsync -a $GOV_MA_GIT_SRC_DIR/ $GOV_MA_WORK_DIR/

    echo "build: fazendo build dos assets"

    # troca pro 1000, pro user "node" conseguir escrever
    chown 1000:1000 $GOV_MA_WORK_DIR/ -R

    deploy_build_assets

    echo "build: descompatando vendors..."
    tar -xf $GOV_MA_CI_GIT/vendor/$EE_CURRENT_VERSION --directory $GOV_MA_WORK_DIR/data/system/

    tar -xf $GOV_MA_CI_GIT/vendor/themes.tar.gz --directory $GOV_MA_WORK_DIR/data/html/

    cp $GOV_MA_USER_ENV_FILE $GOV_MA_WORK_DIR/data/system/user/config/.env

    # volta pro 33 que é o que o apache vai usar
    chown 33:33 $GOV_MA_WORK_DIR/data/ -R

    echo "build: sincronizando diretorio de uploads $GOV_MA_WORK_DIR/data/html/uploads com $GOV_MA_UPLOAD_DIR"

    rsync -a $GOV_MA_WORK_DIR/data/html/uploads/.[^.]* $GOV_MA_UPLOAD_DIR/
    rsync -a $GOV_MA_WORK_DIR/data/html/uploads/* $GOV_MA_UPLOAD_DIR/

    echo "build: apagando diretorio $GOV_MA_WORK_DIR/data/html/uploads"
    rm -rf $GOV_MA_WORK_DIR/data/html/uploads

    echo "build: criando link simbolico para pasta de uploads"
    cd $GOV_MA_WORK_DIR/data/html
    ln -s ../../../uploads uploads
    chown -h 33:33 uploads

    echo "build: sincronizando diretorio de imagens $GOV_MA_WORK_DIR/data/html/images com $GOV_MA_IMAGE_DIR"

    rsync -a $GOV_MA_WORK_DIR/data/html/images/.[^.]* $GOV_MA_IMAGE_DIR/
    rsync -a $GOV_MA_WORK_DIR/data/html/images/* $GOV_MA_IMAGE_DIR/

    echo "build: apagando diretorio $GOV_MA_WORK_DIR/data/html/images"
    rm -rf $GOV_MA_WORK_DIR/data/html/images

    echo "build: criando link simbolico para pasta de images"
    cd $GOV_MA_WORK_DIR/data/html
    ln -s ../../../images images
    chown -h 33:33 images

    GOV_MA_BUILD_DIR="$GOV_MA_SERVER_BASE_DIR/data-build--$BUILD_TS"

    echo "build: renomeando $GOV_MA_WORK_DIR/data para $GOV_MA_BUILD_DIR"
    mv $GOV_MA_WORK_DIR/data $GOV_MA_BUILD_DIR

    # nesse passo, podemos incluir alguns testes, por exemplo, subir o container um novo container
    # do apache conectado nas mesmas networks (logo, mesmo banco da produção) e fazer um GET na homepage ou outro lugar que faça os testes de conexão e templates, etc
    # e se a resposta for 200, entao temmos mais chance desse novo código ir pro ar e tambem dar 200

}

deploy_build_dir() {

    [ ! -d "$GOV_MA_BUILD_DIR" ] && echo "GOV_MA_BUILD_DIR [$GOV_MA_BUILD_DIR] não existe! Deploy não será efetuado!" && exit

    echo "build: elevando $GOV_MA_BUILD_DIR para current-version"
    cd $GOV_MA_SERVER_BASE_DIR

    ln -s "data-build--$BUILD_TS" symlink_new_link

    # ensure the link is owned by 33:33
    chown -h 33:33 symlink_new_link

    mv -T symlink_new_link current-version

    set +x
    printf ">-------------------------------------------<\n           successfully deployed\n>-------------------------------------------<\n\n"

    # força a atualização do mtime de todos os arquivos css e js
    find ./current-version/system/user/ -regex '\(.*css\|.*js\)' -type f -exec touch "{}" \;

}

deploy_build_assets() {
    cd $GOV_MA_WORK_DIR/docker/builder
    docker build . -t gov-ma-builder

    # just in case
    rm -rf $GOV_MA_WORK_DIR/node_modules

    # if the directory was created empty by root on first time
    chown 1000:1000 $NODE_MODULES_CACHE_DIR

    docker run --rm -v $GOV_MA_WORK_DIR:/src -v $NODE_MODULES_CACHE_DIR:/src/node_modules -u node gov-ma-builder \
        sh -c 'cd /src; npm install && npm run build:docs && npm run prod'

}

prepare_source_dir

prepare_build_dir

deploy_build_dir

