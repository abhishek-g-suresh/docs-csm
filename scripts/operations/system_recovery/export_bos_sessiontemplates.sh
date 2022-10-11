#! /bin/sh

################################################################################
# This script exports all existing BOS session templates.
# Specifically, it creates an archive file containing a JSON file for each
# session template. These files can be used to re-create the session templates.
#
# The name of the archive file is defined in the ARCHIVE variable.
################################################################################
ARCHIVE="bos-session-templates.tgz"

if [ -e ${ARCHIVE} ]; then
    echo "Error archive file '${ARCHIVE}' already exists!";
    exit 1;
fi

# Create a JSON file for each session template
TMPDIR=`mktemp -d` || exit 1;
for st in $(cray bos v2 sessiontemplates list --format json | jq .[].name|tr -d \"); do
    cray bos v2 sessiontemplates describe $st --format json > ${TMPDIR}/${st}.json;
done

# Store the JSON files in an archive
tar --create --file ${ARCHIVE} -v -z -C ${TMPDIR} . 1>/dev/null
echo "BOS session templates stored in archive: ${ARCHIVE}"

# Clean up
rm -rf $TMPDIR
