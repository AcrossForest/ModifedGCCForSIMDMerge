#!/usr/bin/env fish

# reference:
# https://preshing.com/20141119/how-to-build-a-gcc-cross-compiler/

# prequisite:
# sudo apt-get install g++ make gawk bison

set thisScriptPath (dirname (realpath (status -f) ) )
set installPath $thisScriptPath/ModifiedToolchain

# set mirror
set GNU_MIRROR https://mirrors.aliyun.com/gnu
set LINUX_MIRROR https://mirrors.aliyun.com/linux-kernel
set GCCINFR_MIRROR http://ftp.tsukuba.wide.ad.jp/software/gcc/infrastructure

set JOBS -j(nproc)
set MACHTYPE x86_64-pc-linux-gnu

if contains all $argv
    set argv $argv download unpack setlink buildall
end

if contains buildall $argv
    set argv $argv setlink step-1 step-2 step-3 step-4-conf step-4-build step-5 step-6 step-7
end


if contains download $argv
    # you don't download from the official binutils, use our modified version instead
    # if not test -e binutils-2.35.tar.xz  
    #     wget $GNU_MIRROR/binutils/binutils-2.35.tar.xz
    # end

    # you don't need to manually download the official GCC, use our modified version instead
    # if not test -e gcc-10.1.0.tar.gz
    #     wget $GNU_MIRROR/gcc/gcc-10.1.0/gcc-10.1.0.tar.gz
    # end

    if not test -e linux-3.17.2.tar.xz
        wget $LINUX_MIRROR/v3.x/linux-3.17.2.tar.xz
    end

    if not test -e glibc-2.31.tar.xz
        wget $GNU_MIRROR/glibc/glibc-2.31.tar.xz
    end

    if not test -e mpfr-3.1.2.tar.xz
        wget $GNU_MIRROR/mpfr/mpfr-3.1.2.tar.xz
    end

    if not test -e gmp-6.0.0a.tar.xz
        wget $GNU_MIRROR/gmp/gmp-6.0.0a.tar.xz
    end

    if not test -e mpc-1.0.2.tar.gz
        wget $GNU_MIRROR/mpc/mpc-1.0.2.tar.gz
    end

    if not test -e isl-0.18.tar.bz2
        wget $GCCINFR_MIRROR/isl-0.18.tar.bz2
    end

    if not test -e cloog-0.18.1.tar.gz
        wget $GCCINFR_MIRROR/cloog-0.18.1.tar.gz
    end 
end

function read_confirm
    read -l -P $argv[1]" Confirm? [y/N]: " Confirm
    switch $Confirm
        case Y y
            return 0
    end
    echo "Don't do anything."
    return 1
end

        

if contains unpack $argv
    if read_confirm "I will unpack. Unpack will overwrite some source folders."
        for zipfile in *.tar*
            if read_confirm "I will unpack "$zipfile" and will overwrite this source folder."
                tar xf $zipfile
            end
        end
    end
end

if contains setlink; or contains step-0 $argv
    pushd gcc-10.1.0
        ln -s ../mpfr-3.1.2 mpfr
        ln -s ../gmp-6.0.0 gmp
        ln -s ../mpc-1.0.2 mpc
        ln -s ../isl-0.18 isl
        ln -s ../cloog-0.18.1 cloog

        pushd isl

            autoreconf -f -i
        popd
    popd 
end

if contains reconfigure $argv; or contains step-0 $argv
    # This is a fix to a bug
    # It appears to cause a problem to clone source files from git instead of unzip from a tar
    # git dosen't preserve the timestamp and inappropriatly forgot to automatically triger something and it requires you to provide aclocal-1.15 which you don't have (you have aclocal-1.16)
    # I only see this problem for isl currently. But to prevent further issues, I do it for all of them.
    pushd binutils-2.35
        autoreconf -f -i
    popd
    pushd gcc-10.1.0
        pushd mpfr
            autoreconf -f -i
        popd
        pushd gmp
            autoreconf -f -i
        popd
        pushd mpc
            autoreconf -f -i
        popd
        pushd isl
            autoreconf -f -i
        popd
        pushd cloog
            autoreconf -f -i
        popd
        autoreconf -f -i
    popd

end


if not test -e $installPath
    mkdir -p $installPath
end
set -x PATH $installPath/bin $PATH

if contains build-binutils $argv; or contains step-1 $argv
    rm -rf build-binutils
    mkdir -p build-binutils
    pushd build-binutils
    ../binutils-2.35/configure --prefix=$installPath --target=aarch64-linux --disable-multilib
    make $JOBS
    make install
    popd
end

if contains reconf-binutils $argv
    rm -rf build-binutils
    mkdir -p build-binutils
    pushd build-binutils
    ../binutils-2.35/configure --prefix=$installPath --target=aarch64-linux --disable-multilib
    popd
end

if contains rebuild-binutils $argv
    pushd build-binutils
    make $JOBS
    make install
    popd
end
    

if contains linux-header $argv; or contains step-2 $argv
    pushd linux-3.17.2
    make ARCH=arm64 INSTALL_HDR_PATH=$installPath/aarch64-linux headers_install
    popd
end

if contains build-gcc-round-1 $argv; or contains step-3 $argv
    rm -rf build-gcc
    mkdir -p build-gcc
    pushd build-gcc
    ../gcc-10.1.0/configure --prefix=$installPath --target=aarch64-linux --enable-languages=c,c++ --disable-multilib --disable-libsanitizer 
    make all-gcc $JOBS
    make install-gcc
    popd
end

if contains build-glibc-round-1-configure $argv; or contains step-4-conf; or contains step-4 $argv
    rm -rf build-glibc
    mkdir -p build-glibc
    pushd build-glibc
    ../glibc-2.31/configure --prefix=$installPath/aarch64-linux --build=$MACHTYPE --host=aarch64-linux --target=aarch64-linux --with-headers=$installPath/aarch64-linux/include --disable-multilib libc_cv_forced_unwind=yes
    popd
end

if contains build-glibc-round-1-build $argv; or contains step-4-build; or contains step-4 $argv
    pushd build-glibc
    make install-bootstrap-headers=yes install-headers
    make $JOBS csu/subdir_lib
    install csu/crt1.o csu/crti.o csu/crtn.o $installPath/aarch64-linux/lib
    aarch64-linux-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o $installPath/aarch64-linux/lib/libc.so
    touch $installPath/aarch64-linux/include/gnu/stubs.h
    popd
end

if contains build-gcc-round-2 $argv; or contains step-5 $argv
    pushd build-gcc
    make $JOBS all-target-libgcc
    make install-target-libgcc
    popd 
end

if contains build-glibc-round-2 $argv; or contains step-6 $argv
    pushd build-glibc
    make $JOBS
    make install
    popd
end

if contains build-gcc-round-3 $argv;or contains rebuild-gcc $argv; or contains step-7 $argv
    pushd build-gcc
    make $JOBS
    make install
    popd
end

if contains testFish $argv
    if read_confirm "I will do something"
        echo yes
    end
end