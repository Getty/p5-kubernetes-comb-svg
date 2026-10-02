requires 'Carp';
requires 'Moo';
requires 'namespace::autoclean';
requires 'Scalar::Util';
requires 'Types::Standard';

on test => sub {
  requires 'JSON::MaybeXS';
  requires 'Path::Tiny';
  requires 'Test::More';
};
