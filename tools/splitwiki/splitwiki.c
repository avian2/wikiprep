/* SpliWiki, split Wikipedia dump into multiple files                      */
/* Copyright (C) 2009 Tomaz Solc                                           */

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

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <zlib.h>

#define MAXLINELEN	(5 * 1024 * 1024)

#define PAGE_START	"  <page>\n"
#define PAGE_END	"  </page>\n"

void syntax() 
{
	printf("SYNTAX: splitwiki num_split prefix\n");
	exit(0);
}

void split(int num_split, gzFile *files[]) {

	int file = -1;

	char *buffer, *r;

	buffer = malloc(MAXLINELEN*sizeof(*buffer));

	while(1) {
		r=fgets(buffer, MAXLINELEN, stdin);

		if(r==NULL) return;

		if(!strcmp(buffer, PAGE_START)) {
			file = random()%num_split;
		}

		if(file == -1) {
			int n;
			for(n = 0; n < num_split; n++) gzputs(files[n], buffer);
		} else {
			gzputs(files[file], buffer);

		}

		if(!strcmp(buffer, PAGE_END)) {
			file = -1;
		}
	}

	free(buffer);
}

int main(int argc, char *argv[]) {
	int n;

	if(argc != 3) syntax();

	int num_split;
	n = sscanf(argv[1], "%d", &num_split);
	if( n != 1 ) syntax();

	char *prefix = argv[2];

	gzFile **files = malloc(sizeof(*files) * num_split);
	for(n = 0; n < num_split; n++) {
		char filename[1024];
		sprintf(filename, "%s.%04d.gz", prefix, n);

		files[n] = gzopen(filename, "w");

		if( files[n] == NULL ) {
			printf("%s: %s\n", filename, strerror(errno));
			return 1;
		}
	}

	split(num_split, files);

	for(n = 0; n < num_split; n++) {
		gzclose(files[n]);
	}

	free(files);

	return 0;
}
