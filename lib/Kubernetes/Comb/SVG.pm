package Kubernetes::Comb::SVG;
# ABSTRACT: Render Kubernetes::Comb custom resources as an SVG honeycomb

use Moo;
use namespace::autoclean;

our $VERSION = '0.001';

1;

=head1 SYNOPSIS

  use Kubernetes::Comb::SVG;

  my $svg = Kubernetes::Comb::SVG->new( combs => \@combs )->render;

=head1 DESCRIPTION

Draws a set of L<Kubernetes::Comb> custom resources as one self-contained SVG
document: a honeycomb with one hexagon per Comb, coloured by its phase.

=cut
