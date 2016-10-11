#!/usr/bin/env bash

PROJECT=$1
RELEASE_VERSION=$2
VERSION_FAMILY=$3
WORKSPACE=${WORKSPACE:-'.'}

if [ -z "$PROJECT" ]; then
	echo "ERROR: Project not supplied"
	exit 1
fi
if [ -z "$RELEASE_VERSION" ]; then
	echo "ERROR: Release version argument not supplied"
	exit 1
fi
if [ -z "$VERSION_FAMILY" ]; then
	echo "ERROR: Version family argument not supplied"
	exit 1
fi

pushd ${WORKSPACE}

unzip distribution/target/hibernate-$PROJECT-$RELEASE_VERSION-dist.zip -d distribution/target/unpacked
DOCUMENTATION_DIRECTORY=distribution/target/unpacked/hibernate-${PROJECT}-${RELEASE_VERSION}/docs

# Add various metadata to the header

if [ "$PROJECT" == "validator" ]; then
	META_DESCRIPTION="Hibernate Validator, Annotation based constraints for your domain model - Reference Documentation"
	META_KEYWORDS="hibernate, validator, hibernate validator, validation, bean validation"
elif [ "$PROJECT" == "ogm" ]; then
	META_DESCRIPTION="Hibernate OGM, JPA for NoSQL datastores - Reference Documentation"
	META_KEYWORDS="hibernate, ogm, hibernate ogm, nosql, jpa, infinispan, mongodb, neo4j, cassandra, couchdb, ehcache, redis"
elif [ "$PROJECT" == "search" ]; then
	META_DESCRIPTION="Hibernate Search, full text search for your entities - Reference Documentation"
	META_KEYWORDS="hibernate, search, hibernate search, full text, lucene, elasticsearch"
else
	META_DESCRIPTION=""
	META_KEYWORDS=""
fi

find ${DOCUMENTATION_DIRECTORY}/reference/ -name \*.html -exec sed -i 's@</title><link rel="stylesheet"@</title><!-- HibernateDoc.Meta --><meta name="description" content="'"$META_DESCRIPTION"'" /><meta name="keywords" content="'"$META_KEYWORDS"'" /><meta name="viewport" content="width=device-width, initial-scale=1.0" /><link rel="canonical" href="https://docs.jboss.org/hibernate/stable/'"$PROJECT"'/reference/en-US/html_single/" /><!-- /HibernateDoc.Meta --><link rel="stylesheet"@' {} \;

# Add the outdated content Javascript at the bottom of the pages

find ${DOCUMENTATION_DIRECTORY}/reference/ -name \*.html -exec sed -i 's@</body>@<!-- HibernateDoc.OutdatedContent --><script src="//code.jquery.com/jquery-3.1.0.min.js" integrity="sha256-cCueBR6CsyA4/9szpPfrX3s49M9vUU5BgtiJj06wt/s=" crossorigin="anonymous"></script><script src="/hibernate/_outdated-content/outdated-content.js" type="text/javascript"></script><script type="text/javascript">var jQuery_3_1 = $.noConflict(true); jQuery_3_1(document).ready(function() { HibernateDoc.OutdatedContent.install("'"$PROJECT"'"); });</script><!-- /HibernateDoc.OutdatedContent --></body>@' {} \;

# Push the documentation to the doc server

rsync -rzh --progress --delete --protocol=28 ${DOCUMENTATION_DIRECTORY}/ filemgmt.jboss.org:/docs_htdocs/hibernate/${PROJECT}/$VERSION_FAMILY

# If the release is the new stable one, we need to update the doc server (outdated content descriptor and /stable/ symlink)

function version_gt() {
	test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1";
}

if [[ $RELEASE_VERSION =~ .*\.Final ]]; then
	wget -q http://docs.jboss.org/hibernate/_outdated-content/${PROJECT}.json -O ${PROJECT}.json
	if [ ! -s ${PROJECT}.json ]; then
		echo "Error downloading the ${PROJECT}.json descriptor. Exiting."
		exit 1
	fi
	CURRENT_STABLE_VERSION=$(cat ${PROJECT}.json | jq -r ".stable")

	if [ "$CURRENT_STABLE_VERSION" != "$VERSION_FAMILY" ] && version_gt $VERSION_FAMILY $CURRENT_STABLE_VERSION; then
		cat ${PROJECT}.json | jq ".stable = \"$VERSION_FAMILY\"" > ${PROJECT}-updated.json
		if [ ! -s ${PROJECT}-updated.json ]; then
			echo "Error updating the ${PROJECT}.json descriptor. Exiting."
			exit 1
		fi

		scp ${PROJECT}-updated.json filemgmt.jboss.org:docs_htdocs/hibernate/_outdated-content/${PROJECT}.json
		rm -f ${PROJECT}-updated.json

		# update the symlink of stable to the latest release
		# don't indent the EOF!
		sftp filemgmt.jboss.org -b <<EOF
cd docs_htdocs/hibernate/stable
rm ${PROJECT}
ln -s ../${PROJECT}/$VERSION_FAMILY ${PROJECT}
EOF
	fi
	rm -f ${PROJECT}.json
fi

popd
