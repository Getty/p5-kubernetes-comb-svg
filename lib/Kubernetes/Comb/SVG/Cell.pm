package Kubernetes::Comb::SVG::Cell;
# ABSTRACT: One Comb custom resource, normalised for layout and drawing

use Moo;
use Carp qw( croak );
use Scalar::Util qw( blessed );
use Types::Standard qw( ArrayRef Bool HashRef Maybe Str );
use namespace::autoclean;

our $VERSION = '0.001';

has name => ( is => 'ro', isa => Str, required => 1 );

has namespace => ( is => 'ro', isa => Maybe[Str] );

has id => ( is => 'lazy', isa => Str, init_arg => undef );

sub _build_id {
  my ( $self ) = @_;
  return defined $self->namespace ? $self->namespace.'/'.$self->name : $self->name;
}

has class => ( is => 'ro', isa => Maybe[Str] );

has phase => ( is => 'ro', isa => Str, default => 'Unknown' );

has raw_phase => ( is => 'ro', isa => Maybe[Str] );

has enabled => ( is => 'ro', isa => Bool, default => 1 );

has depends_on => ( is => 'ro', isa => ArrayRef[Str], default => sub { [] } );

has dependencies => ( is => 'rwp', isa => ArrayRef[Str], init_arg => undef, default => sub { [] } );

has missing => ( is => 'rwp', isa => ArrayRef[Str], init_arg => undef, default => sub { [] } );

has endpoints => ( is => 'ro', isa => ArrayRef[HashRef], default => sub { [] } );

has borrowed => ( is => 'ro', isa => Bool, default => 0 );

has upstream_context => ( is => 'ro', isa => Maybe[Str] );

has upstream_via => ( is => 'ro', isa => ArrayRef[Str], default => sub { [] } );

has group => ( is => 'ro', isa => Maybe[Str] );

has message => ( is => 'ro', isa => Maybe[Str] );

sub known_phases { qw( Running Pending Blocked NeedsConfig Disabled Error ) }

sub is_known_phase {
  my ( $self, $phase ) = @_;
  return 0 unless defined $phase;
  return scalar grep { $_ eq $phase } $self->known_phases;
}

sub from_cr {
  my ( $self, $cr, %opt ) = @_;
  $cr = $self->_hash($cr);
  my $meta   = $self->_hash( $cr->{metadata} );
  my $spec   = $self->_hash( $cr->{spec} );
  my $status = $self->_hash( $cr->{status} );

  my $name = $self->_str( $meta->{name} );
  croak __PACKAGE__.'->from_cr: Comb without metadata.name'
    unless defined $name;

  my $enabled   = $self->_enabled( $spec->{enabled} );
  my $raw_phase = $self->_str( $status->{phase} );
  my $phase     = !$enabled                         ? 'Disabled'
                : $self->is_known_phase($raw_phase) ? $raw_phase
                :                                     'Unknown';

  my $upstream = $self->_hash( $status->{upstream} );
  my $label    = $self->_str( $opt{group_label} );

  return $self->new(
    name             => $name,
    namespace        => $self->_str( $meta->{namespace} ),
    class            => $self->_str( $spec->{class} ),
    phase            => $phase,
    raw_phase        => $raw_phase,
    enabled          => $enabled,
    depends_on       => [ $self->_strings( $spec->{dependsOn} ) ],
    endpoints        => [ $self->_endpoints( $status->{endpoints} ) ],
    borrowed         => ( %$upstream ? 1 : 0 ),
    upstream_context => $self->_str( $upstream->{context} ),
    upstream_via     => [ $self->_strings( $upstream->{via} ) ],
    group            => defined $label
      ? $self->_str( $self->_hash( $meta->{labels} )->{$label} )
      : undef,
    message          => $phase eq 'Running'
      ? undef
      : $self->_message( $status->{conditions} )
  );
}

sub cells_from {
  my ( $self, $input, %opt ) = @_;
  $input = $self->_plain($input);
  my @crs = ref $input eq 'ARRAY' ? @$input
          : ref $input eq 'HASH' && exists $input->{items}
            ? $self->_list( $input->{items} )
          : defined $input ? ( $input )
          :                  ();
  my ( @cells, %by_id, %by_name );
  for my $cr (@crs) {
    my $cell = $self->from_cr( $cr, %opt );
    next if $by_id{ $cell->id };
    $by_id{ $cell->id } = $cell;
    push @{ $by_name{ $cell->name } }, $cell;
    push @cells, $cell;
  }
  $_->_resolve( \%by_id, \%by_name ) for @cells;
  return @cells;
}

# Sorts depends_on into the ids of cells in the set and the entries that
# match none, or more than one.
sub _resolve {
  my ( $self, $by_id, $by_name ) = @_;
  my ( @dependencies, @missing, %seen );
  for my $entry ( @{ $self->depends_on } ) {
    my $cell = $self->_dependency( $entry, $by_id, $by_name );
    push @missing, $entry unless $cell;
    push @dependencies, $cell->id if $cell && !$seen{ $cell->id }++;
  }
  $self->_set_dependencies( \@dependencies );
  $self->_set_missing( \@missing );
  return;
}

# 'namespace/name' is an id. A bare name is the cell of that name in the own
# namespace, else the only cell of that name.
sub _dependency {
  my ( $self, $entry, $by_id, $by_name ) = @_;
  return $by_id->{$entry} if index( $entry, '/' ) >= 0;
  my $own = $by_id->{ defined $self->namespace ? $self->namespace.'/'.$entry : $entry };
  return $own if $own;
  my @named = @{ $by_name->{$entry} || [] };
  return @named == 1 ? $named[0] : undef;
}

#### Reading odd data

# An object answering TO_JSON becomes what it answers; anything else stays.
sub _plain {
  my ( $self, $value ) = @_;
  my $hops = 0;
  $value = $value->TO_JSON
    while blessed $value && $value->can('TO_JSON') && $hops++ < 8;
  return $value;
}

sub _hash {
  my ( $self, $value ) = @_;
  $value = $self->_plain($value);
  return ref $value eq 'HASH' ? $value : {};
}

sub _list {
  my ( $self, $value ) = @_;
  $value = $self->_plain($value);
  return ref $value eq 'ARRAY' ? @$value : ();
}

# A non-empty plain scalar, as a string; everything else is undef.
sub _str {
  my ( $self, $value ) = @_;
  return undef if !defined $value || ref $value || !length $value;
  return ''.$value;
}

# A list of names: an array of strings, or one string. No duplicates, order kept.
sub _strings {
  my ( $self, $value ) = @_;
  $value = $self->_plain($value);
  my %seen;
  return grep { defined && !$seen{$_}++ }
    map { $self->_str($_) }
    ref $value eq 'ARRAY' ? @$value : ( $value );
}

# spec.enabled is tri-state: unset is automatic, only a false value switches off.
sub _enabled {
  my ( $self, $value ) = @_;
  return 1 unless defined $value;
  return 0 unless $value;
  return 1 if ref $value;
  return lc $value eq 'false' ? 0 : 1;
}

sub _endpoints {
  my ( $self, $value ) = @_;
  my @endpoints;
  for my $entry ( $self->_list($value) ) {
    $entry = $self->_hash($entry);
    my $name = $self->_str( $entry->{name} );
    next unless defined $name;
    push @endpoints, { name => $name, port => $self->_str( $entry->{port} ) };
  }
  return @endpoints;
}

sub _message {
  my ( $self, $value ) = @_;
  my %seen;
  my @messages = grep { defined && !$seen{$_}++ }
    map { $self->_str( $self->_hash($_)->{message} ) } $self->_list($value);
  return @messages ? join( "\n", @messages ) : undef;
}

1;

=head1 SYNOPSIS

  use Kubernetes::Comb::SVG::Cell;

  my $cell = Kubernetes::Comb::SVG::Cell->from_cr( $cr,
    group_label => 'app.kubernetes.io/part-of' );

  my @cells = Kubernetes::Comb::SVG::Cell->cells_from($list_or_array_or_cr);

=head1 DESCRIPTION

The only place a C<Comb> custom resource is read. A cell carries the plain
values layout and drawing need; nothing here is escaped. Odd data degrades
quietly -- only a Comb without C<metadata.name> is an error.

=attr name

C<metadata.name>. Required.

=attr namespace

C<metadata.namespace>, or C<undef>.

=attr id

C<namespace/name>, or L</name> alone without a namespace. What dependencies
refer to and what makes a cell unique in a set. Not a constructor argument.

=attr class

C<spec.class>, or C<undef>.

=attr phase

One of L</known_phases> or C<Unknown>.

=attr raw_phase

C<status.phase> as the custom resource has it, or C<undef>.

=attr enabled

False when C<spec.enabled> is false; L</phase> is C<Disabled> then.

=attr depends_on

ArrayRef of the entries in C<spec.dependsOn> as they came, each C<name> or
C<namespace/name>.

=attr dependencies

ArrayRef of the L</id>s of the cells this one depends on, in the order of
L</depends_on>, without duplicates. Filled by L</cells_from>; empty on a cell
built alone. Not a constructor argument.

=attr missing

ArrayRef of the L</depends_on> entries that match no cell of the set, or more
than one. Filled by L</cells_from>; empty on a cell built alone. Not a
constructor argument.

=attr endpoints

ArrayRef of C<< { name => ..., port => ... } >> from C<status.endpoints>.

=attr borrowed

True when C<status.upstream> is present.

=attr upstream_context

C<status.upstream.context>, or C<undef>.

=attr upstream_via

ArrayRef of the names in C<status.upstream.via>.

=attr group

Value of the label named by C<group_label>, or C<undef>.

=attr message

The condition messages, one per line, when L</phase> is not C<Running>.

=method from_cr

  my $cell = Kubernetes::Comb::SVG::Cell->from_cr( $cr, group_label => $key );

Builds a cell from a hash in CR shape or an object answering C<TO_JSON>.

=method cells_from

  my @cells = Kubernetes::Comb::SVG::Cell->cells_from( $input, group_label => $key );

Takes an array of custom resources, a C<List> hash with C<items>, or one
custom resource, and returns the cells in input order. Of several with one
L</id> the first is kept.

Dependencies are resolved over the whole set into L</dependencies> and
L</missing>: C<namespace/name> is the cell with that L</id>; a bare C<name> is
the cell of that name in the dependent's own namespace, else the only cell of
that name in the set.

=method known_phases

The phases that are drawn as themselves.

=method is_known_phase

  $cell->is_known_phase('Running');

=seealso

=over

=item * L<Kubernetes::Comb::SVG>

=back

=cut
