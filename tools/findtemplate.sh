#!/bin/bash

if [ "$#" -lt "2" ]; then
	cat<<END
Find templates that support a named parameter
SYNTAX: findtemplates path_to_template_dir named_parameter

Example: findtemplates enwiki-20080312-pages-articles.templates isbn
END
	exit 0
fi

TEMPLATEDIR="$1"
PARAMNAME="$2"

OLDDIR=`pwd`

cd "$TEMPLATEDIR"

grep -rci "^$PARAMNAME = " 1 2 3 4 5 6 7 8 9 | (
	while read T; do
		TEMPLATEID=`echo $T | sed -e 's/^.*\///' | sed -e 's/:[0-9]\+$//'`
		TEMPLATETITLE=`grep "^$TEMPLATEID[^0-9]" index`
		PAGENUM=`echo $T | sed -e 's/^.*://'`

		if [ "x$PAGENUM" != "x0" ]; then
			echo "$TEMPLATETITLE ($PAGENUM)"
		fi
	done
)
