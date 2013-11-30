#!/bin/sh

CURRDIR=`pwd`
rm -Rf docs-*
for VERSION in develop `git tag -l`; do
	TMPDIR=/tmp/ouroboros-docs-$VERSION
	DESTDIR=docs-$VERSION
	rm -Rf $TMPDIR && rm -Rf $DESTDIR && mkdir -p $TMPDIR && \
		(git archive $VERSION | tar -xC $TMPDIR) && \
		cd $TMPDIR && \
		nimrod doc2 ouroboros.nim && \
		nimrod doc2 alchemy.nim ; \
		cd "${CURRDIR}" && \
		mkdir $DESTDIR && \
		cp $TMPDIR/ouroboros.html $DESTDIR && \
		cp $TMPDIR/alchemy.html $DESTDIR ; \
		git add docs-*
done

cat index.html.pre > index.html

for f in `ls docs-*/*html`; do
	echo "<li><a href=\"${f}\">${f}</a>" >> index.html
done
cat index.html.post >> index.html

git status;
echo "Finished updating docs, please remember to add the link to index.html!"
