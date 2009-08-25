#!/bin/bash

if [ "$#" -lt "2" ]; then
	cat<<END
Find templates that have a named parameter
SYNTAX: findtemplates path_to_template_dir named_parameter

Example: findtemplates enwiki-20080312-pages-articles.xml isbn
END
	exit 0
fi

XMLPATH="$1"
PARAMNAME="$2"

GUMPATH=`echo "$XMLPATH" | sed -e 's/\.xml/.gum.xml/'`
TMPLPATH=`echo "$XMLPATH" | sed -e 's/\.xml/.tmpl.xml/'`

OLDDIR=`pwd`

zcat "$GUMPATH"*gz | sed -ne "/^<template id=/{s/[^0-9]//g;h};/^<param name=\"$PARAMNAME\">/I{g;p}" | sort | uniq -c | sort -n | (
	while read T; do
		TMPLNUM=`echo $T | awk '{ print $1 }'`
		TMPLID=`echo $T | awk '{ print $2 }'`

		TMPLTITLE=`grep -B1 "$TMPLID" "$TMPLPATH" | head -n1 | sed -e 's/<[^<]\+>//g'`

		printf "%8d %s\n" "$TMPLNUM" "$TMPLTITLE"
	done
)
