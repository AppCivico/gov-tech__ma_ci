#!/bin/bash
set -e

BUILD_TS=$(date '+%F-%Hh%Mm%Ss')

HOME="/home/$USER"

EE_CURRENT_VERSION="ee.6.0.6.patched.tar.gz"

# diretorio com o source deste proprio deploy.sh!
GOV_MA_CI_GIT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

set -x

# diretorio com o source code para a nova versao
GOV_MA_GIT_SRC_DIR="${GOV_MA_GIT_SRC_DIR:-$HOME/gov_ma_git}"

# diretorio onde existe o link simbólico para a versao corrente, e onde serao criados as novas versoes
GOV_MA_SERVER_BASE_DIR="${GOV_MA_SERVER_BASE_DIR:-$HOME/gov_ma_server}"

# diretorio com os uploads que sempre são os mesmos entre todas as versoes do site
GOV_MA_UPLOAD_DIR="${GOV_MA_UPLOAD_DIR:-$HOME/gov_ma_uploads}"

[ ! -d "$GOV_MA_SERVER_BASE_DIR" ] && echo "GOV_MA_SERVER_BASE_DIR [$GOV_MA_SERVER_BASE_DIR] não existe. Configurare o diretorio base (este diretorio precisa ser montado no container do apache)" && exit
[ ! -d "$GOV_MA_UPLOAD_DIR" ] && echo "GOV_MA_UPLOAD_DIR [$GOV_MA_UPLOAD_DIR] não existe. Diretorio de upload persistente precisa existir!" && exit
[ ! -d "$GOV_MA_CI_GIT" ] && echo "GOV_MA_CI_GIT [$GOV_MA_CI_GIT] não existe ou não está configurado corretamente" && exit

# testando se os arquivos do CI existem
[ ! -f "$GOV_MA_CI_GIT/deploy.sh" ] && echo "[$GOV_MA_CI_GIT/deploy.sh] não existe!" && exit
[ ! -d "$GOV_MA_CI_GIT/vendor" ] && echo "[$GOV_MA_CI_GIT/vendor] não existe!" && exit
[ ! -f "$GOV_MA_CI_GIT/vendor/$EE_CURRENT_VERSION" ] && echo "[$GOV_MA_CI_GIT/vendor/$EE_CURRENT_VERSION] não existe!" && exit

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

    [ -d "$GOV_MA_WORK_DIR"] echo "build: apagando $GOV_MA_WORK_DIR. build anterior incompleto?" && rm -rf $GOV_MA_WORK_DIR

    echo "build: Criando diretorio para build GOV_MA_WORK_DIR [$GOV_MA_WORK_DIR]" && mkdir -p $GOV_MA_WORK_DIR

    echo "build: Clonando $GOV_MA_GIT_SRC_DIR/ para $GOV_MA_WORK_DIR/"

    rsync -a --stats $GOV_MA_GIT_SRC_DIR/ $GOV_MA_WORK_DIR/

    chown 33:33 $GOV_MA_WORK_DIR/data/ -R

    echo "build: descompatando vendors..."
    tar -xf $GOV_MA_CI_GIT/vendor/$EE_CURRENT_VERSION --directory $GOV_MA_WORK_DIR/data/system/

    echo "build: sincronizando diretorio de uploads $GOV_MA_WORK_DIR/data/html/uploads com $GOV_MA_UPLOAD_DIR"

    rsync -a --stats $GOV_MA_WORK_DIR/data/html/uploads/.[^.]* $GOV_MA_UPLOAD_DIR/

    echo "build: apagando diretorio $GOV_MA_WORK_DIR/data/html/uploads"
    rm -rf $GOV_MA_WORK_DIR/data/html/uploads

    echo "build: criando link simbólico de $GOV_MA_UPLOAD_DIR para $GOV_MA_WORK_DIR/data/html/uploads"
    ln -s $GOV_MA_UPLOAD_DIR $GOV_MA_WORK_DIR/data/html/uploads

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
    ln -s $GOV_MA_BUILD_DIR symlink_new_link && mv -T symlink_new_link current-version

}

prepare_source_dir

prepare_build_dir

deploy_build_dir



