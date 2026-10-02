# Kubernetes::Comb::SVG

Render [Kubernetes::Comb](https://metacpan.org/pod/Kubernetes::Comb) custom
resources as an SVG honeycomb.

## Synopsis

```perl
use Kubernetes::Comb::SVG;

my $svg = Kubernetes::Comb::SVG->new(
  combs       => \@combs,              # Comb CRs: hashes or IO::K8s objects
  title       => 'Lab',
  group_label => 'app.kubernetes.io/part-of',
)->render;
```

```bash
kubectl get combs -A -o json | comb-svg > combs.svg
```

## Description

One hexagon per Comb, coloured by its phase, placed below the Combs it
depends on, with the dependencies drawn as edges. The result is one
self-contained SVG document — no script, no external font or stylesheet — that
follows the viewer's light or dark mode and can be embedded in any page.

The dist does not talk to a cluster and ships no server: it turns the CRs you
hand it into a picture. The design is in [SPEC.md](SPEC.md).

## License

This is free software; you can redistribute it and/or modify it under the same
terms as the Perl 5 programming language system itself.
