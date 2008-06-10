# vim:sw=2:tabstop=2:expandtab

use strict;

package utils;

sub trimWhitespaceBothSides(\$) {
    my ($stringRef) = @_;

    # remove leading whitespace
    $$stringRef =~ s/^\s*//;
    # remove trailing whitespace
    $$stringRef =~ s/\s*$//;
}

1
