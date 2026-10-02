#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

for (qw(
  Kubernetes::Comb::SVG
  Kubernetes::Comb::SVG::Cell
)) {
  use_ok($_);
}

done_testing;
