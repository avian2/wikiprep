# vim:sw=2:tabstop=2:expandtab

package Wikiprep::Statistics;

use strict;
use warnings;

use Exporter 'import';

use Log::Handler wikiprep => 'LOG';

use Wikiprep::utils qw( getLinkIds removeDuplicatesAndSelf );

our @EXPORT_OK = qw( updateStatistics updateCategoryHierarchy 
		                 %catHierarchy %statCategories %statIncomingLinks );

# each category is associated with a list of its immediate descendants
our %catHierarchy;       

# number of pages classified under each category
our %statCategories;     

# number of links incoming to each page
our %statIncomingLinks;  

sub updateStatistics {
  my ($page) = @_;

  for my $cat (@{$page->{categories}}) {
    $statCategories{$cat}++;
  }

  my @internalLinks;

  &getLinkIds(\@internalLinks, $page->{wikiLinks});
  &removeDuplicatesAndSelf(\@internalLinks, $page->{id});

  for my $link (@internalLinks) {
    $statIncomingLinks{$link}++;
  }
}

sub updateCategoryHierarchy {
  # The list of categories passed as a parameter is actually the list of parent categories
  # for the current category
  my ($page) = @_;

  for my $parentCat (@{$page->{categories}}) {
    if( exists($catHierarchy{$parentCat}) ) {
      push(@{$catHierarchy{$parentCat}}, $page->{id});
    } else {
      # create a new array with '$childId' as the only child (for now) of '$parentCat'
      $catHierarchy{$parentCat} = [ $page->{id} ];
    }
  }
}

1;
