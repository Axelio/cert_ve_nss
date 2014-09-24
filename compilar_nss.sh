#!/usr/bin/env shell

mkdir -p ~/public_html/certificados_iceweasel/certificados/
mkdir -p ~/public_html/certificados_iceweasel/paquetes/
cd ~/public_html/certificados_iceweasel/

echo "Instalando dependencias necesarias"
su -c "aptitude install git git-buildpackage build-essential quilt libc6-dev-i386 lib32z1-dev libnspr4-dev libsqlite3-dev"

echo " "
echo "Iniciando procedimiento para obtencion del certificado"
git clone https://gist.github.com/Axelio/0a86cddf72dadfd43426 get_certificados

echo " "
echo "Descargando los siguientes certificados:"
cd certificados/
python ~/public_html/certificados_iceweasel/get_certificados/descargar_certificados.py

echo " "
echo "Obteniendo código fuente de nss y nspr"
cd ~/public_html/certificados_iceweasel/paquetes/
rm -rf ~/public_html/certificados_iceweasel/get_certificados/
apt-get source nss nspr

cd ~/public_html/certificados_iceweasel/paquetes/nss-3.14.5/
export QUILT_PATCHES=debian/patches
quilt pop -a

echo "Compilando la herramienta addbuiltin"
git init
git add .
git commit -a -m "Versión original del código fuente."

cd ~/public_html/certificados_iceweasel/paquetes/nss-3.14.5/mozilla/
ln -s ~/public_html/certificados_iceweasel/paquetes/nspr-4.9.2/mozilla/nsprpub/ .

COMMAND=`uname -r`
echo $LIST
ARCH="amd64"

su -c '
    if echo "$COMMAND" | grep -q "$SOURCE"; then
        cd ~/public_html/certificados_iceweasel/paquetes/nss-3.14.5/mozilla/security/nss/
        make nss_build_all BUILD_OPT=1 USE_64=1

        cd ~/public_html/certificados_iceweasel/paquetes/nss-3.14.5/mozilla/security/nss/cmd/addbuiltin/
        make BUILD_OPT=1 USE_64=1

        echo " "
        echo "Se copiará Linux3.2_x86_64_glibc_PTH_64_OPT.OBJ a /usr/bin/"
        echo "Se debe ejecutar como super usuario"
        cp -v Linux3.2_x86_64_glibc_PTH_64_OPT.OBJ/addbuiltin /usr/bin/"
    else
        cd ~/public_html/certificados_iceweasel/paquetes/nss-3.14.5/mozilla/security/nss/
        make nss_build_all BUILD_OPT=1

        cd ~/public_html/certificados_iceweasel/paquetes/nss-3.14.5/mozilla/security/nss/cmd/addbuiltin/
        make BUILD_OPT=1

        echo " "
        echo "Se copiará Linux3.2_x86_glibc_PTH_OPT.OBJ a /usr/bin/"
        echo "Se debe ejecutar como super usuario"
        su -c "cp -v Linux3.2_x86_glibc_PTH_OPT.OBJ/addbuiltin /usr/bin/"
    fi
'

echo " "
echo "Convirtiendo los certificados con addbuiltin"
cd ~/public_html/certificados_iceweasel/certificados/

CERTIFICADOS=`ls *.crt`

for certificado in $CERTIFICADOS
    do
        nombre=`echo $certificado | cut -d \. -f 1`
        openssl x509 -inform PEM -outform DER -in $certificado -out $nombre.der
        comando=`openssl x509 -inform PEM -text -in $certificado | grep "Subject"`
        O=`echo $comando| cut -d \O -f 2`
        O=`echo $O| cut -d \= -f 2`
        O=`echo $O| cut -d \, -f 1`
        comando=`cat $nombre.der | addbuiltin -n "$O" -t "C,C,C" > $nombre.nss`
done

echo " "
echo "Parcheando y reempaquetando NSS"
cd ~/public_html/certificados_iceweasel/paquetes/nss-3.14.5/
git reset --hard
git clean -fd

version=`dpkg-parsechangelog | grep "Version:" | awk '{print $2}'`
version=`echo $version | cut -d \: -f 2`

git tag debian/$version

cd ~/public_html/certificados_iceweasel/certificados/

CERTIFICADOS=`ls *.nss`

for certificado in $CERTIFICADOS
    do
        cat $certificado >> ~/public_html/certificados_iceweasel/paquetes/nss-3.14.5/mozilla/security/nss/lib/ckfw/builtins/certdata.txt
done

cd ~/public_html/certificados_iceweasel/paquetes/nss-3.14.5/mozilla/security/nss/lib/ckfw/builtins/
make generate


cd ~/public_html/certificados_iceweasel/paquetes/nss-3.14.5/
mkdir -p debian/patches

echo " "
echo "Generando parches"
git diff > ../99_ACR-certificates.patch
git reset --hard
git clean -fd
mv ../99_ACR-certificates.patch debian/patches/
echo "99_ACR-certificates.patch" >> debian/patches/series

echo " "
echo "Comprobando parches"
export QUILT_PATCHES=debian/patches
quilt push -af
quilt refresh
rm -rf mozilla/security/nss/lib/ckfw/builtins/certdata.c.rej
quilt pop -a

git add .
git commit -am "Agregando parche para los certificados aprobados por SUSCERTE"
git-buildpackage -us -uc
