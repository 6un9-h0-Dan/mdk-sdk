LLVER=${LLVM_VER:-12}
NDK_HOST=linux
FF_EXTRA=-clang
FFPKG_EXT=tar.xz

echo "EXTERNAL_DEP_CACHE_HIT: ${EXTERNAL_DEP_CACHE_HIT}"
echo "DEVTOOLS_CACHE_HIT: ${DEVTOOLS_CACHE_HIT}"

du -hc external

if [[ "$TARGET_OS" == mac* || "$TARGET_OS" == iOS* || "$TARGET_OS" == android ]]; then
    FF_EXTRA=
fi
if [[ "$TARGET_OS" == "win"* || "$TARGET_OS" == "uwp"* ]]; then
  FF_EXTRA=-vs2019
  FFPKG_EXT=7z
fi
if [ `which dpkg` ]; then # TODO: multi arch
    pkgs="sshpass cmake ninja-build p7zip-full"
    #wget https://apt.llvm.org/llvm.sh
    if [[ "$TARGET_OS" != android ]]; then
      pkgs+=" lld-$LLVER clang-tools-$LLVER" # clang-tools: clang-cl
      wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key |sudo apt-key add -
      #sudo apt update
      #sudo apt install -y software-properties-common # for add-apt-repository, ubuntu-tooolchain-r-test is required by trusty
      #sudo apt-add-repository "deb http://apt.llvm.org/focal/ llvm-toolchain-focal-8 main" # rpi
      sudo apt-add-repository "deb http://apt.llvm.org/focal/ llvm-toolchain-focal-12 main"
      sudo apt-add-repository "deb http://apt.llvm.org/focal/ llvm-toolchain-focal main" # clang-13
      sudo apt update
    fi
    if [ "$TARGET_OS" == "linux" ]; then
        pkgs+=" libc++-$LLVER-dev libc++abi-$LLVER-dev libegl1-mesa-dev libgles2-mesa-dev libgl1-mesa-dev libgbm-dev libx11-dev libwayland-dev libasound2-dev libopenal-dev libpulse-dev libva-dev libvdpau-dev libglfw3-dev libsdl2-dev"
    elif [ "$TARGET_OS" == "sunxi" -o "$TARGET_OS" == "raspberry-pi" ]; then
        pkgs+=" binutils-arm-linux-gnueabihf"
    fi
    sudo apt install -y $pkgs
elif [ `which brew` ]; then
    #time brew update --preinstall
    export HOMEBREW_NO_AUTO_UPDATE=1
    pkgs="p7zip ninja vulkan-headers dav1d" #
    if [[ "$DEVTOOLS_CACHE_HIT" != "true" ]]; then
        pkgs+=" hudochenkov/sshpass/sshpass"
    fi
    if [ "$TARGET_OS" == "macOS" ]; then
        pkgs+=" glfw3 sdl2"
        echo "$TARGET_ARCH" |grep arm >/dev/null || { # FIXME: arm64 host build
          time brew cask install xquartz
          pkgs+=" pulseaudio"
        }
    fi
    time brew install $pkgs
    NDK_HOST=darwin
fi

OS=${TARGET_OS/r*pi/rpi}
OS=${OS/*store/WinRT}
OS=${OS/*uwp*/WinRT}
OS=${OS%%-*}
OS=${OS/Simulator/}
[ "$TARGET_OS" == "linux" ] && OS=Linux
mkdir -p external/{bin,lib}/$OS

if [[ "$EXTERNAL_DEP_CACHE_HIT" != "true" ]]; then
  FFPKG=ffmpeg-${FF_VER}-${TARGET_OS}${FF_EXTRA}-lite${LTO_SUFFIX}
  curl -kL -o ffmpeg-${TARGET_OS}.${FFPKG_EXT} https://sourceforge.net/projects/avbuild/files/${TARGET_OS}/${FFPKG}.${FFPKG_EXT}/download
  if [[ "${FFPKG_EXT}" == 7z ]]; then
    7z x ffmpeg-${TARGET_OS}.${FFPKG_EXT}
  else
    tar Jxf ffmpeg-${TARGET_OS}.${FFPKG_EXT}
  fi
  #find ${FFPKG}/lib -name "libav*.so*" -o  -name "libsw*.so*" -delete

  cp -af ${FFPKG}/lib/* external/lib/$OS
  cp -af ${FFPKG}/include external/
  cp -af ${FFPKG}/bin/* external/bin/$OS # ffmpeg dll

  if [ "$TARGET_OS" == "sunxi" ]; then
      mkdir -p external/lib/sunxi/armv7
      cp -af ${FFPKG}/lib/* external/lib/sunxi/armv7 #single arch package
  elif [ "$TARGET_OS" == "windows-desktop" ]; then
      curl -kL -o glfw3.7z https://sourceforge.net/projects/mdk-sdk/files/deps/glfw3.7z/download
      7z x glfw3.7z
      cp -af glfw3/include/GLFW external/include/
      cp -af glfw3/lib/* external/lib/windows/
      # TODO: download in cmake(if check_include_files failed)
      curl -kL -o vk.zip https://github.com/KhronosGroup/Vulkan-Headers/archive/master.zip
      7z x vk.zip
      cp -af Vulkan-Headers-master/include/vulkan external/include/
  fi

  if [[ "$TARGET_OS" == "win"* || "$TARGET_OS" == "uwp"* || "$TARGET_OS" == macOS ]]; then
    mkdir -p external/include/{EGL,GLES{2,3},KHR}
    for h in GLES2/gl2.h GLES2/gl2ext.h GLES2/gl2platform.h GLES3/gl3.h GLES3/gl3platform.h; do
      curl -kL -o external/include/${h} https://www.khronos.org/registry/OpenGL/api/${h}
    done
    for h in EGL/egl.h EGL/eglext.h EGL/eglplatform.h KHR/khrplatform.h; do
      curl -kL -o external/include/${h} https://www.khronos.org/registry/EGL/api/${h}
    done
  fi
fi

if [[ "$SYSROOT_CACHE_HIT" != "true" ]]; then
  if [[ "$TARGET_OS" == "win"* || "$TARGET_OS" == "uwp"* ]]; then
    wget https://sourceforge.net/projects/avbuild/files/dep/msvcrt-dev.7z/download -O msvcrt-dev.7z
    echo 7z x msvcrt-dev.7z -o${WINDOWSSDKDIR%/?*}
    7z x msvcrt-dev.7z -o${WINDOWSSDKDIR%/?*}
    wget https://sourceforge.net/projects/avbuild/files/dep/winsdk.7z/download -O winsdk.7z
    echo 7z x winsdk.7z -o${WINDOWSSDKDIR%/?*}
    7z x winsdk.7z -o${WINDOWSSDKDIR%/?*}
    ${WINDOWSSDKDIR}/lowercase.sh
    ${WINDOWSSDKDIR}/mkvfs.sh
  fi

  if [ "$TARGET_OS" == "sunxi" -o "$TARGET_OS" == "raspberry-pi" -o "$TARGET_OS" == "linux" ]; then
    wget https://sourceforge.net/projects/avbuild/files/${TARGET_OS}/${TARGET_OS/r*pi/rpi}-sysroot.tar.xz/download -O sysroot.tar.xz
    tar Jxf sysroot.tar.xz
  fi

  if [ "$TARGET_OS" == "android" -a ! -d "$ANDROID_NDK_LATEST_HOME" ]; then
    wget https://dl.google.com/android/repository/android-ndk-${NDK_VERSION:-r22b}-${NDK_HOST}-x86_64.zip -O ndk.zip
    7z x ndk.zip -o/tmp &>/dev/null
    mv /tmp/android-ndk-${NDK_VERSION:-r22b} ${ANDROID_NDK:-/tmp/android-ndk}
  fi
fi

if [[ "$EXTERNAL_DEP_CACHE_HIT" != "true" ]]; then
  curl -kL -o dav1d.deb "https://www.deb-multimedia.org/pool/main/d/dav1d-dmo/libdav1d-dev_0.9.0-dmo1_armhf.deb"
  7z x -y dav1d.deb
  tar xvf data.tar
  mv usr/include/dav1d external/include/
fi