#!/usr/bin/env shell
 
EXITO() {
printf "\033[1;32m${1}\033[0m\n"
}
 
PATH_CERTS='/tmp/certificados'
PATH_MOZILLA='~/public_html/certificados_iceweasel'

mkdir -p $PATH_MOZILLA/certificados/
mkdir -p $PATH_MOZILLA/paquetes/
mkdir -p $PATH_CERTS
cd $PATH_MOZILLA
 
EXITO "Instalando dependencias necesarias"
su -c "aptitude update; aptitude install git git-buildpackage build-essential quilt libc6-dev zlib1g-dev libnspr4-dev libsqlite3-dev canaima-certificados"
 
echo " "
EXITO "Obteniendo código fuente de nss y nspr"
cd $PATH_MOZILLA/paquetes/
apt-get source nss nspr
 
echo " "
EXITO "Quitando patchs"
VERSION_NSS=`ls -d */ | grep nss | cut -d \- -f 2 | cut -d \/ -f 1`
VERSION_NSPR=`ls -d */ | grep nspr | cut -d \- -f 2 | cut -d \/ -f 1`
VERSION_NSS_CHANGELOG=`head -1 ~/public_html/certificados_iceweasel/paquetes/nss-$VERSION_NSS/debian/changelog | tail -1 | cut -d \( -f 2 | cut -d \) -f 1` 
 
cd $PATH_MOZILLA/paquetes/nss-$VERSION_NSS/
export QUILT_PATCHES=debian/patches
quilt pop -a
rm -rf .pc
 
EXITO "Compilando la herramienta addbuiltin"
git init
git add .
git commit -a -m "Versión original del código fuente."
 
cd $PATH_MOZILLA/paquetes/nss-$VERSION_NSS/mozilla/
ln -s $PATH_MOZILLA/paquetes/nspr-$VERSION_NSPR/mozilla/nsprpub/ .
 
echo $LIST
 
su -c '
    if echo "$COMMAND" | grep -q "$SOURCE"; then
        cd $PATH_MOZILLA/paquetes/nss-$VERSION_NSS/mozilla/security/nss/
        make nss_build_all BUILD_OPT=1 USE_64=1
         
        cd $PATH_MOZILLA/paquetes/nss-$VERSION_NSS/mozilla/security/nss/cmd/addbuiltin/
        make BUILD_OPT=1 USE_64=1
         
        echo " "
        echo "Se copiará Linux3.2_x86_64_glibc_PTH_64_OPT.OBJ a /usr/bin/"
        echo "Se debe ejecutar como super usuario"
        cp -v Linux3.2_x86_64_glibc_PTH_64_OPT.OBJ/addbuiltin /usr/bin/"
    else
        cd $PATH_MOZILLA/paquetes/nss-$VERSION_NSS/mozilla/security/nss/
        make nss_build_all BUILD_OPT=1
         
        cd $PATH_MOZILLA/paquetes/nss-$VERSION_NSS/mozilla/security/nss/cmd/addbuiltin/
        make BUILD_OPT=1
         
        echo " "
        echo "Se copiará Linux3.2_x86_glibc_PTH_OPT.OBJ a /usr/bin/"
        echo "Se debe ejecutar como super usuario"
        su -c "cp -v Linux3.2_x86_glibc_PTH_OPT.OBJ/addbuiltin /usr/bin/"
    fi
'
 
echo " "
EXITO "Convirtiendo los certificados con addbuiltin"
cp /etc/ssl/certs/* $PATH_CERTS
 
CERTIFICADOS=`ls $PATH_CERTS`
 
for certificado in $CERTIFICADOS
    do
        if [ `echo $certificado | cut -d \. -f 2;` != 0 ]; then
            nombre=`echo $certificado | cut -d \. -f 1`
        else
            nombre=$certificado
        fi
        openssl x509 -inform PEM -outform DER -in $certificado -out $nombre.der
        comando=`openssl x509 -inform PEM -text -in $certificado | grep "Subject"`
        O=`echo $comando | cut -d \O -f 2 | cut -d \= -f 2 | cut -d \, -f 1`
        comando=`cat $nombre.der | addbuiltin -n "$O" -t "C,C,C" > $nombre.nss`
    done
 
echo " "
echo "Parcheando y reempaquetando NSS"
cd $PATH_MOZILLA/paquetes/nss-$VERSION_NSS/
git reset --hard
git clean -fd
 
version=`dpkg-parsechangelog | grep "Version:" | awk '{print $2}'`
version=`echo $version | cut -d \: -f 2`
 
git tag debian/$version
 
cd $PATH_MOZILLA/certificados/
 
CERTIFICADOS=`ls *.nss`
 
for certificado in $CERTIFICADOS
    do
        cat $certificado >> $PATH_MOZILLA/paquetes/nss-$VERSION_NSS/mozilla/security/nss/lib/ckfw/builtins/certdata.txt
    done
 
cd $PATH_MOZILLA/paquetes/nss-$VERSION_NSS/mozilla/security/nss/lib/ckfw/builtins/
make generate
 
 
cd PATH_MOZILLA/paquetes/nss-$VERSION_NSS/
mkdir -p debian/patches
 
echo " "
EXITO "Generando parches"
git diff > ../99_ACR-certificates.patch
git reset --hard
git clean -fd
mv ../99_ACR-certificates.patch debian/patches/
echo "99_ACR-certificates.patch" >> debian/patches/series
 
echo " "
EXITO "Comprobando parches"
export QUILT_PATCHES=debian/patches
quilt push -af
quilt refresh
rm -rf mozilla/security/nss/lib/ckfw/builtins/certdata.c.rej
quilt pop -a
rm -rf .pc
 
echo " "
EXITO "Subiendo de versión el paquete NSS"
git dch -N $VERSION_NSS_CHANGELOG+1canaima --release --auto --id-length=7 --full --git-author
 
git add .
git commit -am "Agregando parche para los certificados de los Proveedores de Servicios de Certificación por SUSCERTE"
git-buildpackage -us -uc -j5
