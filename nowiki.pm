# vim:sw=2:tabstop=2:expandtab

use strict;

package nowiki;

# This function is used to create random strings that are used as temporary tokens in Wikipedia articles 
# being parsed. It must produce a string that has a very low probability of appearing in Wikipedia.
#
# Replicates behaviour of getRandomString() function from MediaWiki Parser.php:

# * Prefix for temporary replacement strings for the multipass parser.
# * \x07 should never appear in input as it's disallowed in XML.
# * Using it at the front also gives us a little extra robustness
# * since it shouldn't match when butted up against identifier-like
# * string constructs.
# *
# * Must not consist of all title characters, or else it will change 
# * the behaviour of <nowiki> in a link.

# Note that MediaWiki actually uses \x7f, not \x07

sub randomString() {
  return sprintf("\x7fUNIQ%08x%08x", rand(0x7fffffff), rand(0x7fffffff));
}

# extractTags() Extracts all substrings matching the given regular expression from text and stores
# them in a hash. Substrings are replaced by unique tokens. replaceTags() does the reverse and
# replaces tokens in text back with the original substrings. These two functions are used to hide
# parts of the text from certain parts of the parser.
#
# Regular expression may be compiled, and must be enclosed in parenthesis.

sub extractTags($\$\%) {
  my ($regex, $refToText, $refToChunksReplaced) = @_;

  $$refToText =~ s/$regex/&extractOneTag($1, $refToChunksReplaced)/seg;
}

BEGIN {

my $randomTokenRegex = qr/(\x7fUNIQ[0-9a-f]{16})/;

sub replaceTags(\$\%) {
  my ($refToText, $refToChunksReplaced) = @_;

  # Don't invoke s/// if there is nothing to replace
  return if((scalar keys(%$refToChunksReplaced)) < 1);

  $$refToText =~ s/$randomTokenRegex/&replaceOneTag($1, $refToChunksReplaced)/seg;
}

}

sub extractOneTag($\%) {
  my ($content, $RefToChunksReplaced) = @_;

  my $token = &randomString();

  $$RefToChunksReplaced{$token} = $content;

  return $token;
}

sub replaceOneTag($\%) {
  my ($token, $RefToChunksReplaced) = @_;

  my $content = $$RefToChunksReplaced{$token};

  if(not defined($content)) {

    # This looks like a token, but it really isn't since it isn't in the hash. So leave it
    # unmodified.
    return $token;
  } else {
    return $content;
  }
}

1
