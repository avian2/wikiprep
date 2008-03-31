use Test::Harness;

@INC = ("..");

$Test::Harness::verbose = 1;

runtests(@ARGV);
