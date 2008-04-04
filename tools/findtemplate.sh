#!/bin/bash

if [ "$#" -lt "2" ]; then
	cat<<END
Find templates that support a named parameter
SYNTAX: findtemplates path_to_template_dir named_parameter

Example: findtemplates enwiki-20080312-pages-articles.templates isbn
END
fi

TEMPLATEDIR="$1"
PARAMNAME="$2"

OLDDIR=`pwd`

cd "$TEMPLATEDIR"

for T in `grep -rl "^$PARAMNAME = " *`; do
	TEMPLATEID=`echo $T | sed -e 's/^.*\///'`
	TEMPLATETITLE=`grep $TEMPLATEID index`
	PAGENUM=`grep '^Page ' $T | wc -l`

	echo "$TEMPLATETITLE ($PAGENUM)"
done
