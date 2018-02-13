#!/bin/bash

function usage() {
    echo
    echo "Changes the image.*.yaml files and regenerates the build directories"
    echo 'Commits the changes on a branch release_$RELEASE, ready for a push'
    echo
    echo "Usage: release.sh [options]"
    echo
    echo "required arguments"
    echo
    echo "  -r RELEASE          The oshinko release number, like v0.4.4"
    echo
    echo "optional arguments:"
    echo
    echo "  -o OSHINKO_VERSION  If not specified, the oshinko version will be set to RELEASE"
    echo
    echo "  -s SPARK_VERSION    The spark version, like 2.2.1"
    echo "                      This value is used to download the spark distribution, and for the"
    echo "                      scala image it's used to determine the openshift-spark base image"
    echo
    echo "  -l SCALA_VERSION    The scala version, like 2.11.8. Applies to the scala image"
    echo
    echo "  -t SBT_VERSION      The sbt version, like 0.13.13. Applies to the scala image"
    echo
    echo "  -h                  Show this message"
}

if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

# Set a default for the hadoop version
HVER=2.7

while getopts r:o:s:l:t:h opt; do
    case $opt in
        o)
            OVER=$OPTARG
            ;;
        s)
            SPARK=$OPTARG
            ;;
	l)
	    SCALA=$OPTARG
	    ;;
	t)
	    SBT=$OPTARG
	    ;;
        h)
            usage
            exit 0
            ;;
	r)
	    NEW_VERSION=$OPTARG
	    ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

if [ -z ${NEW_VERSION+x} ]; then
    echo "Error: no release specified"
    usage
    exit 1
fi

git checkout -b release_$NEW_VERSION

if [ -z ${OVER+x} ]; then
    OVER=$NEW_VERSION
fi

wget https://github.com/radanalyticsio/oshinko-cli/releases/download/${OVER}/oshinko_${OVER}_linux_amd64.tar.gz -O /tmp/oshinko_${OVER}_linux_amd64.tar.gz
if [ "$?" -eq 0 ]; then

    sum=$(md5sum /tmp/oshinko_${OVER}_linux_amd64.tar.gz | cut -d ' ' -f 1)

    # Fix the url references
    sed -i "s@https://github.com/radanalyticsio/oshinko-cli/releases/download/.*@https://github.com/radanalyticsio/oshinko-cli/releases/download/${OVER}/oshinko_${OVER}_linux_amd64.tar.gz@" image.*.yaml

    # Fix the md5sum on the line following the url
    sed -i '\@url: https://github.com/radanalyticsio/oshinko-cli/releases/download@!b;n;s/md5.*/md5: '$sum'/' image.*.yaml
else
    echo "Failed to get the md5 sum for the specified oshinko version, the version $OVER may not be a real version"
    exit 1
fi

# Change spark distro and download urls
if [ ! -z ${SPARK+x} ]; then

    # Change the md5sum for pyspark and java, update base image for scala
    wget https://archive.apache.org/dist/spark/spark-${SPARK}/spark-${SPARK}-bin-hadoop${HVER}.tgz.md5 -O /tmp/spark-${SPARK}-bin-hadoop${HVER}.tgz.md5
    if [ "$?" -eq 0 ]; then

        sum=$(cat /tmp/spark-${SPARK}-bin-hadoop2.7.tgz.md5 | cut -d':' -f 2 | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

	# Fix the url references
	sed -i "s@https://archive.apache.org/dist/spark/spark-.*/spark-.*-bin-@https://archive.apache.org/dist/spark/spark-${SPARK}/spark-${SPARK}-bin-@" image.*.yaml

	# Fix the md5 sum references on the line following the url
        sed -i '\@url: https://archive.apache.org/dist/spark/@!b;n;s/md5.*/md5: '$sum'/' image.*.yaml

        # For the scala image, the openshift-spark base image is based on the first 2 characters in the spark version
        BV=$(echo ${SPARK} | cut -d'.' -f1,2)
        sed -i "s@radanalyticsio/openshift-spark:.*-latest@radanalyticsio/openshift-spark:${BV}-latest@" image.*.yaml
    else
        echo "Failed to get the md5 sum for the specified spark version, the version $SPARK may not be a real version"
        exit 1
    fi
fi

# Change scala version (scala image only)
if [ ! -z ${SCALA+x} ]; then
    wget http://downloads.lightbend.com/scala/${SCALA}/scala-${SCALA}.tgz -O /tmp/scala-${SCALA}.tgz
    if [ "$?" -eq 0 ]; then
        sum=$(md5sum /tmp/scala-${SCALA}.tgz | cut -d ' ' -f 1)

        # Fix up the yaml files to hold the url for the new version of scala
        sed -i "s@http://downloads.lightbend.com/scala.*@http://downloads.lightbend.com/scala/${SCALA}/scala-${SCALA}.tgz@" image.*.yaml

        # Replace the md5sum for the tarball on the line following the url
        sed -i '\@url: http://downloads.lightbend.com/scala/@!b;n;s/md5.*/md5: '$sum'/' image.*.yaml

    else
        echo "Failed to get the md5 sum for the specified scala version, the version $SCALA may not be a real version"
        exit 1
    fi
fi

# Change the sbt version (scala image only)
if [ ! -z ${SBT+x} ]; then
    wget http://dl.bintray.com/sbt/native-packages/sbt/${SBT}/sbt-${SBT}.tgz -O /tmp/sbt-${SBT}.tgz
    if [ "$?" -eq 0 ]; then
        sum=$(md5sum /tmp/sbt-${SBT}.tgz | cut -d ' ' -f 1)

        # Fix up the yaml files to hold the url for the new version of scala
        sed -i "s@http://dl.bintray.com/sbt/native-packages/sbt/.*@http://dl.bintray.com/sbt/native-packages/sbt/${SBT}/sbt-${SBT}.tgz@" image.*.yaml

        # Replace the md5sum for the tarball on the line following the url
        sed -i '\@url: http://dl.bintray.com/sbt/native-packages/sbt/@!b;n;s/md5.*/md5: '$sum'/' image.*.yaml

    else
        echo "Failed to get the md5 sum file for the specified sbt version, the version $SBT may not be a real version"
        exit 1
    fi
fi

rm -rf target
git rm pyspark-build/oshinko*.tar.gz
git rm java-build/oshinko*.tar.gz
git rm scala-build/oshinko*.tar.gz
make clean-context
make context
make zero-tarballs

git add pyspark-build/oshinko*.tar.gz
git add java-build/oshinko*.tar.gz
git add scala-build/oshinko*.tar.gz
git commit -a -m "Change oshinko CLI version to $OVER"
