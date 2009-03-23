# vim:sw=2:tabstop=2:expandtab

package Wikiprep::Namespace;

use strict;

use Exporter 'import';
use Hash::Util qw( lock_hash );

our @EXPORT_OK = qw( normalizeTitle normalizeNamespace loadNamespaces isNamespaceOk resolveNamespaceAliases isTitleOkForLocalPages isKnownNamespace );

# List of known namespaces defined in the header of the XML file
my %namespaces;

# Title normalization
# ===========================================================================================================

sub normalizeNamespace(\$) {
  my ($refToStr) = @_;

  # Namespaces are always lowercase with capitalized first letter.
  $$refToStr = ucfirst( lc($$refToStr) );
}

# This is the function for normalizing titles - It transforms page titles into a form that is
# used throughout Wikiprep to uniquely identify pages, templates, categories, etc.
#
# It does not strip namespace declarations.
#
# FIXME defaultNamespace parameter (then replace computeFullyQualifiedTemplateTitle)

sub normalizeTitle(\$) {
  my ($refToStr) = @_;

  # remove leading whitespace and underscores
  $$refToStr =~ s/^[\s_]+//;
  # remove trailing whitespace and underscores
  $$refToStr =~ s/[\s_]+$//;
  # replace sequences of whitespace and underscore chars with a single space
  $$refToStr =~ s/[\s_]+/ /g;

  if ($$refToStr =~ /^([^:]*):(\s*)(\S(?:.*))/) {
    my $prefix = $1;
    my $optionalWhitespace = $2;
    my $rest = $3;

    my $namespaceCandidate = $prefix;
    # this must be done before the call to 'isKnownNamespace'
    &normalizeNamespace(\$namespaceCandidate); 
    if ( &isKnownNamespace(\$namespaceCandidate) ) {
      # If the prefix designates a known namespace, then it might follow by optional
      # whitespace that should be removed to get the canonical page name
      # (e.g., "Category:  Births" should become "Category:Births").
      $$refToStr = $namespaceCandidate . ":" . ucfirst($rest);
    } else {
      # No namespace, just capitalize first letter.
      # If the part before the colon is not a known namespace, then we must not remove the space
      # after the colon (if any), e.g., "3001: The_Final_Odyssey" != "3001:The_Final_Odyssey".
      # However, to get the canonical page name we must contract multiple spaces into one,
      # because "3001:   The_Final_Odyssey" != "3001: The_Final_Odyssey".
      $$refToStr = ucfirst($prefix) . ":" . $optionalWhitespace . $rest;
    }
  } else {
    # no namespace, just capitalize first letter
    $$refToStr = ucfirst($$refToStr);
  }
}

# Prescan
# ===========================================================================================================

# Load namespaces (during prescan)
sub loadNamespaces() {
  my ($pages) = @_;

  # namespace names are case-insensitive, so we force them
  # to canonical form to facilitate future comparisons
  for my $ns ( @{$pages->namespaces} ) {

    my $id = $ns->[0];
    my $name = $ns->[1];

    &normalizeNamespace(\$name);
    $namespaces{$name} = $id;
  }

  lock_hash( %namespaces );
}

# Namespace checking
# ===========================================================================================================

# Checks if the prefix of the page name before the colon is actually one of the
# 16+2+2 namespaces defined in the XML file.
# Assumption: the argument was already normalized using 'normalizeNamespace'
sub isKnownNamespace(\$) {
  my ($refToStr) = @_;

  return exists( $namespaces{$$refToStr} );  # return value
}

sub resolveNamespaceAliases(\$) {
  my ($refToTitle) = @_;

  while(my ($key, $value) = each(%Wikiprep::Config::namespaceAliases)) {
      $$refToTitle =~ s/^\s*$key:/$value:/mig;
  }
}

sub isNamespaceOkForLocalPages(\$) {
  my ($refToNamespace) = @_;

  # We are only interested in image links, so main namespace is not OK.
  my $result = 0;

  if ($$refToNamespace ne '') {
    if ( &isKnownNamespace($refToNamespace) ) {
      $result = exists( $Wikiprep::Config::okNamespacesForLocalPages{$$refToNamespace} );
    } else {
      # A simple way to recognize most namespaces that link to translated articles. A better 
      # way would be to store these namespaces in a hash.
      if ( length($$refToNamespace) < 4 ) {
        $result = 0
      }

      # the prefix before ":" in the page title is not a known namespace,
      # therefore, the page belongs to the main namespace and is OK
    }
  }

  $result; # return value
}

sub isNamespaceOk($\%) {
  my ($namespace, $refToNamespaceHash) = @_;

  my $result = 1;

  # main namespace is OK, so we only check pages that belong to other namespaces

  if ($namespace ne '') {
    my $namespace = $namespace;
    &normalizeNamespace(\$namespace);
    if ( &isKnownNamespace(\$namespace) ) {
      $result = exists( $$refToNamespaceHash{$namespace} );
    } else {
      # the prefix before ":" in the page title is not a known namespace,
      # therefore, the page belongs to the main namespace and is OK
    }
  }

  $result; # return value
}

sub isTitleOkForLocalPages(\$) {
  my ($refToPageTitle) = @_;

  my $namespaceOk = 0;

  if ($$refToPageTitle =~ /^:.*$/) {
    # Leading colon by itself implies main namespace
    $namespaceOk = 0;

  # Note that there must be at least one non-space character following the namespace specification
  # for the page title to be valid. If there is none, then the link is considered to point to a
  # page in the main namespace.

  } elsif ($$refToPageTitle =~ /^([^:]*):\s*\S/) {
    # colon found but not in the first position - check if it designates a known namespace
    my $prefix = $1;
    &normalizeNamespace(\$prefix);
    $namespaceOk = &isNamespaceOkForLocalPages(\$prefix);
  }

  # The case when the page title does not contain a colon at all also falls here.

  return $namespaceOk
}

1;
