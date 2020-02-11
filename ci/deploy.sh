#!/bin/bash
set -x
set -e

TARGET_DIR=${1:-target}

if [[ "$TRAVIS" != "" ]] ; then
  DEPLOY_ENV_TYPE="travis"
  TAG_NAME=$TRAVIS_TAG
elif [[ "$APPVEYOR" != "" ]] ; then
  DEPLOY_ENV_TYPE="appveyor"
  TAG_NAME=$APPVEYOR_REPO_TAG_NAME
elif [[ "$TF_BUILD" != "" ]] ; then
  DEPLOY_ENV_TYPE="azure"
elif [[ "$GITHUB_ACTIONS" == "true" ]] ; then
  DEPLOY_ENV_TYPE="github"
else
  DEPLOY_ENV_TYPE="adhoc"
fi

TAG_NAME=${TAG_NAME:-$(git describe --tags)}
TAG_NAME=${TAG_NAME:-$(date +'%Y%m%d-%H%M%S')-$(git log --format=%h -1)}

# Emit the tagname variable for azure to pick up
# https://docs.microsoft.com/en-us/azure/devops/pipelines/troubleshooting?view=azure-devops#variables-having--single-quote-appended
set +x
echo "##vso[task.setvariable variable=wezterm.tagname]$TAG_NAME"
set -x

HERE=$(pwd)

case $OSTYPE in
  darwin*)
    zipdir=WezTerm-macos-$DEPLOY_ENV_TYPE-$TAG_NAME
    if [[ "$BUILD_REASON" == "Schedule" ]] ; then
      zipname=WezTerm-macos-nightly.zip
    else
      zipname=$zipdir.zip
    fi
    rm -rf $zipdir $zipname
    mkdir $zipdir
    cp -r assets/macos/WezTerm.app $zipdir/
    cp $TARGET_DIR/release/wezterm $zipdir/WezTerm.app
    cp -r assets/colors $zipdir/WezTerm.app/Contents/Resources/
    zip -r $zipname $zipdir
    ;;
  msys)
    zipdir=WezTerm-windows-$DEPLOY_ENV_TYPE-$TAG_NAME
    if [[ "$BUILD_REASON" == "Schedule" ]] ; then
      zipname=WezTerm-windows-nightly.zip
    else
      zipname=$zipdir.zip
    fi
    rm -rf $zipdir $zipname
    mkdir $zipdir
    cp $TARGET_DIR/release/wezterm.exe $TARGET_DIR/release/wezterm.pdb $zipdir
    cp -r assets/colors $zipdir/
    7z a -tzip $zipname $zipdir
    ;;
  linux-gnu)
    case `lsb_release -ds` in
      *Fedora*|*CentOS*)
        WEZTERM_RPM_VERSION=$(echo ${TAG_NAME#nightly-} | tr - _)
        cat > wezterm.spec <<EOF
Name: wezterm
Version: ${WEZTERM_RPM_VERSION}
Release: 1%{?dist}
Packager: Wez Furlong <wez@wezfurlong.org>
License: MIT
URL: https://wezfurlong.org/wezterm/
Summary: Wez's Terminal Emulator.
Requires: dbus, fontconfig, openssl, libxcb, libxkbcommon, libxkbcommon-x11, libwayland-client, libwayland-egl, libwayland-cursor, mesa-libEGL, xcb-util-keysyms, xcb-util-wm

%description
wezterm is a terminal emulator with support for modern features
such as fonts with ligatures, hyperlinks, tabs and multiple
windows.

%build
echo "Doing the build bit here"

%install
set -x
cd ${HERE}
mkdir -p %{buildroot}/usr/bin %{buildroot}/usr/share/wezterm/colors %{buildroot}/usr/share/applications
install -Dsm755 target/release/wezterm %{buildroot}/usr/bin
install -Dm644 assets/icon/terminal.png %{buildroot}/usr/share/icons/hicolor/128x128/apps/org.wezfurlong.wezterm.png
install -Dm644 -t %{buildroot}/usr/share/wezterm/colors assets/colors/*
install -Dm644 assets/wezterm.desktop %{buildroot}/usr/share/applications/org.wezfurlong.wezterm.desktop
install -Dm644 assets/wezterm.appdata.xml %{buildroot}/usr/share/metainfo/wezterm.appdata.xml

%files
/usr/bin/wezterm
/usr/share/icons/hicolor/128x128/apps/org.wezfurlong.wezterm.png
/usr/share/wezterm/colors/*
/usr/share/applications/org.wezfurlong.wezterm.desktop
/usr/share/metainfo/wezterm.appdata.xml
EOF

        /usr/bin/rpmbuild -bb --rmspec wezterm.spec --verbose

        ;;
      Ubuntu*|Debian*)
        rm -rf pkg
        mkdir -p pkg/debian/usr/bin pkg/debian/DEBIAN pkg/debian/usr/share/{applications,wezterm}
        cat > pkg/debian/DEBIAN/control <<EOF
Package: wezterm
Version: ${TAG_NAME#nightly-}
Architecture: amd64
Maintainer: Wez Furlong <wez@wezfurlong.org>
Section: utils
Priority: optional
Homepage: https://wezfurlong.org/wezterm/
Description: Wez's Terminal Emulator.
 wezterm is a terminal emulator with support for modern features
 such as fonts with ligatures, hyperlinks, tabs and multiple
 windows.
Depends: libc6, libegl-mesa0, libxcb-icccm4, libxcb-ewmh2, libxcb-keysyms1, libxcb-xkb1, libxkbcommon0, libxkbcommon-x11-0, libfontconfig1, xdg-utils, libxcb-render0, libxcb-shape0, libx11-6, libegl1
EOF
        install -Dsm755 -t pkg/debian/usr/bin target/release/wezterm
        install -Dm644 assets/icon/terminal.png pkg/debian/usr/share/icons/hicolor/128x128/apps/org.wezfurlong.wezterm.png
        install -Dm644 -t pkg/debian/usr/share/wezterm/colors assets/colors/*
        install -Dm644 assets/wezterm.desktop pkg/debian/usr/share/applications/org.wezfurlong.wezterm.desktop
				install -Dm644 assets/wezterm.appdata.xml pkg/debian/usr/share/metainfo/wezterm.appdata.xml
        if [[ "$BUILD_REASON" == "Schedule" ]] ; then
          debname=wezterm-nightly
        else
          debname=wezterm-$TAG_NAME
        fi
        fakeroot dpkg-deb --build pkg/debian $debname.deb
        tar cJf $debname.tar.xz -C pkg/debian/usr/bin wezterm
        rm -rf pkg
        ./ci/appimage.sh
        if [[ "$BUILD_REASON" == "Schedule" ]] ; then
          mv WezTerm*.AppImage WezTerm-nightly.AppImage
        fi
      ;;
    esac
    ./ci/source-archive.sh

    ;;
  *)
    ;;
esac
