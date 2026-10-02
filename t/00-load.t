#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

for (qw(
  Kubernetes::Comb::SVG
)) {
  use_ok($_);
}

done_testing;
