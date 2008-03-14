/* SampleWiki, perform a random sampling of Wikipedia pages                */
/* Copyright (C) 2007 Tomaz Solc                                           */

/* This program is free software; you can redistribute it and/or modify    */
/* it under the terms of the GNU General Public License version 2 as       */
/* published by the Free Software Foundation.                              */

/* This program is distributed in the hope that it will be useful,         */
/* but WITHOUT ANY WARRANTY; without even the implied warranty of          */
/* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           */
/* GNU General Public License for more details.                            */

/* You should have received a copy of the GNU General Public License       */
/* along with this program; if not, write to the Free Software             */
/* Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA */

/* $Id: samplewiki.c,v 1.1 2007/10/24 08:28:04 avian1 Exp $ */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* 1/PART is the probability that a Wikipedia page will end up in the sample
 * For example: PART = 20 will include approximately one in twenty pages and
 * will give you a 650 MB sample. */
#define PART	500

#define MAXLINELEN	(5 * 1024 * 1024)

#define MAXPAGES 	5000

#define TEMPLATE_TITLE	"    <title>Template:"
#define TITLE		"    <title>"

int main() {
	int inPage=0;
	int inGoodMood=0;

	int page_count = 0;

	char *buffer;
	char *r;

	int template_title_len = strlen(TEMPLATE_TITLE);
	int title_len = strlen(TITLE);

	buffer=malloc(MAXLINELEN*sizeof(*buffer));

	while(1) {
		r=fgets(buffer, MAXLINELEN, stdin);

		if(r==NULL) return 0;

		if(!strncmp(buffer, TEMPLATE_TITLE, template_title_len)) {
			inPage = 1;
			inGoodMood = 1;
			fputs("  <page>\n", stdout);
		} else {
			if(!strncmp(buffer, TITLE, title_len)) {
				inPage=1;

				if(MAXPAGES == -1 || page_count < MAXPAGES) {
					inGoodMood = ((random()%PART)==1);
				} else {
					inGoodMood = 0;
				}

				if(inGoodMood) {
					page_count ++;
					fputs("  <page>\n", stdout);
				}
			}
		}

		if((inPage && inGoodMood) || (!inPage)) {
			if(strcmp(buffer, "  <page>\n")) {
				fputs(buffer, stdout);
			}
		}

		if(!strcmp(buffer, "  </page>\n")) {
			inPage=0;
		}
	}

	return 0;
}
