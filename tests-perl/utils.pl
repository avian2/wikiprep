use Test::More tests => 1;
use utils;

is(&utils::trimWhitespaceBothSides("  hello  "), "hello");
