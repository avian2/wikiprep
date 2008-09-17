# vim:sw=2:tabstop=2:expandtab

package Wikiprep::logger;

use strict;
use Exporter 'import';
our @EXPORT_OK = qw( msg );

my %settings = ( DEBUG => 0,
                 WARNING => 0,
                 PROFILE => 0 );

sub init {
  my ($fn, $args) = @_;

  my @splitargs;

  if( $args eq 'all' ) {
    @splitargs = keys( %settings );
  } else {
	  @splitargs = split(/:/, $args);
  }

	for $a ( @splitargs ) {
    if( exists( $settings{ uc($a) } ) ) {
      $settings{ uc($a) } = 1;
    } else {
      die("Invalid log setting: $a");
    }
  }

  open(LOGF, "> $fn") or die "Cannot open $fn: $!";
  binmode(LOGF, ':utf8');
}

sub msg {
  my ($type, $msg) = @_;

  if( $settings{$type} == 1 ) {
    print(LOGF "$type: $msg\n");
    LOGF->flush();
  }
}

sub stop {
  close(LOGF);
}

1
