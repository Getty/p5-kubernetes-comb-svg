#!/usr/bin/env perl
# Renders examples/demo.json to examples/demo.svg, the picture the README
# shows:
#
#   perl -Ilib examples/demo.pl
#
# Both files are found next to this script, so it runs from any directory.
# With a path as argument the picture is written there instead; that is how
# t/50-demo.t checks that the committed demo.svg is current.

use strict;
use warnings;
use JSON::MaybeXS;
use Path::Tiny;
use Kubernetes::Comb::SVG;

my $here = path(__FILE__)->absolute->parent;
my $out  = @ARGV ? path( $ARGV[0] ) : $here->child('demo.svg');

my $combs = JSON::MaybeXS->new( utf8 => 1 )->decode( $here->child('demo.json')->slurp_raw );

$out->spew_raw( Kubernetes::Comb::SVG->new(
  combs       => $combs,
  title       => 'Shop',
  group_label => 'app.kubernetes.io/part-of',
  columns     => 6
)->render );
