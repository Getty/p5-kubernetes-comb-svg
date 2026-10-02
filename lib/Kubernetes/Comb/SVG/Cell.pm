package Kubernetes::Comb::SVG::Cell;
# ABSTRACT: One Comb custom resource, normalised for layout and drawing

=synopsis

  use Kubernetes::Comb::SVG::Cell;

  my $cell = Kubernetes::Comb::SVG::Cell->from_cr( $cr,
    group_label => 'app.kubernetes.io/part-of' );

  my @cells = Kubernetes::Comb::SVG::Cell->cells_from($list_or_array_or_cr);

  for my $cell (@cells) {
    printf "%s %s -> %s\n", $cell->id, $cell->phase,
      join ',', @{ $cell->dependencies };
  }

=description

The only place a C<Comb> custom resource is read. A cell carries the plain
values layout and drawing need; nothing in it is escaped (the drawing does
that). The input is duck-typed: a hash in CR shape, or an object answering
C<TO_JSON>, which is also tried on every section (C<metadata>, C<spec>,
C<status>, ...). The module never talks to a cluster and does not need
L<Kubernetes::Comb> or L<IO::K8s>.

Odd data degrades quietly: a section that is not a hash counts as empty, a
value that is not a plain non-empty string counts as absent, a missing
C<status> gives phase C<Unknown>. Only a Comb without C<metadata.name> is an
error.

=cut

use Moo;
use Carp qw( croak );
use Scalar::Util qw( blessed );
use Types::Standard qw( ArrayRef Bool HashRef Maybe Str );
use namespace::autoclean;

our $VERSION = '0.001';

has name => ( is => 'ro', isa => Str, required => 1 );

=attr name

Required. C<metadata.name>.

=cut

has namespace => ( is => 'ro', isa => Maybe[Str] );

=attr namespace

C<metadata.namespace>, or C<undef> when the custom resource has none.

=cut

has id => ( is => 'lazy', isa => Str, init_arg => undef );

=attr id

C<namespace/name>, or the L</name> alone when there is no namespace. This is
what makes a cell unique in a set (so C<kubectl get combs -A> may carry one
name in two namespaces), what L</dependencies> hold, and what the drawing
puts in C<data-id>. Not a constructor argument.

=cut

sub _build_id {
  my ( $self ) = @_;
  return defined $self->namespace ? $self->namespace.'/'.$self->name : $self->name;
}

has class => ( is => 'ro', isa => Maybe[Str] );

=attr class

C<spec.class>, or C<undef>.

=cut

has phase => ( is => 'ro', isa => Str, default => 'Unknown' );

=attr phase

Default C<Unknown>. The phase the cell is drawn in: C<Disabled> when
L</enabled> is false, else C<status.phase> when it is one of
L</known_phases>, else C<Unknown> (also for a missing C<status>).

=cut

has raw_phase => ( is => 'ro', isa => Maybe[Str] );

=attr raw_phase

C<status.phase> as the custom resource has it, or C<undef> when it is absent
or not a string. It is kept even when L</phase> says something else, so the
tooltip can show what an C<Unknown> cell really reported.

=cut

has enabled => ( is => 'ro', isa => Bool, default => 1 );

=attr enabled

Default true. C<spec.enabled> is read as a tri-state: unset is true; only a
false value switches the cell off (C<false>, the string C<false> in any case,
C<0>, the empty string); any other value is true. A disabled cell has the
phase C<Disabled> even without a C<status>.

=cut

has depends_on => ( is => 'ro', isa => ArrayRef[Str], default => sub { [] } );

=attr depends_on

ArrayRef of the entries of C<spec.dependsOn> as written, each C<name> or
C<namespace/name>, in order, without duplicates. A single string instead of a
list is accepted. Entries that are not plain non-empty strings are dropped.
Not yet resolved; see L</dependencies> and L</missing>.

=cut

has dependencies => ( is => 'rwp', isa => ArrayRef[Str], init_arg => undef, default => sub { [] } );

=attr dependencies

ArrayRef of the L</id>s of the cells this one depends on, in the order of
L</depends_on>, without duplicates. Filled by L</cells_from>; empty on a cell
built alone. A cell that lists itself has its own id here. Not a constructor
argument.

=cut

has missing => ( is => 'rwp', isa => ArrayRef[Str], init_arg => undef, default => sub { [] } );

=attr missing

ArrayRef of the L</depends_on> entries, as written, that match no cell of the
set, or more than one. Filled by L</cells_from>; empty on a cell built alone.
The drawing lists them in the tooltip; they do not take part in the layout.
Not a constructor argument.

=cut

has endpoints => ( is => 'ro', isa => ArrayRef[HashRef], default => sub { [] } );

=attr endpoints

ArrayRef of C<< { name => $name, port => $port } >> from C<status.endpoints>,
in order. C<port> is a string, or C<undef> when the entry has none; an entry
without a C<name> is skipped.

=cut

has borrowed => ( is => 'ro', isa => Bool, default => 0 );

=attr borrowed

Default false. True when C<status.upstream> is present, that is a non-empty
hash: the Comb takes its service from an upstream layer instead of running it.

=cut

has upstream_context => ( is => 'ro', isa => Maybe[Str] );

=attr upstream_context

C<status.upstream.context>, or C<undef>.

=cut

has upstream_via => ( is => 'ro', isa => ArrayRef[Str], default => sub { [] } );

=attr upstream_via

ArrayRef of the names in C<status.upstream.via>, in order, without
duplicates; a single string is accepted.

=cut

has group => ( is => 'ro', isa => Maybe[Str] );

=attr group

The value of the label named by the C<group_label> option in
C<metadata.labels>. C<undef> without that option, without the label, or with
an empty value.

=cut

has message => ( is => 'ro', isa => Maybe[Str] );

=attr message

The C<message> of every entry of C<status.conditions>, each once, joined by
newlines; C<undef> when there is none. Only read when L</phase> is not
C<Running>.

=cut

sub known_phases { qw( Running Pending Blocked NeedsConfig Disabled Error Stopped NotDeployed ) }

=method known_phases

  my @phases = Kubernetes::Comb::SVG::Cell->known_phases;

Returns the phases of C<Kubernetes::Comb> that are drawn as themselves:
C<Running>, C<Pending>, C<Blocked>, C<NeedsConfig>, C<Disabled>, C<Error>,
C<Stopped>, C<NotDeployed> -- the order of its C<CombStatus>. Any other phase
is C<Unknown>. Callable on the class.

=cut

sub is_known_phase {
  my ( $self, $phase ) = @_;
  return 0 unless defined $phase;
  return scalar grep { $_ eq $phase } $self->known_phases;
}

=method is_known_phase

  $cell->is_known_phase('Running');   # true
  $cell->is_known_phase('Starting');  # false

True when the phase is one of L</known_phases>; false for an unknown phase
and for C<undef>.

=cut

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

=method from_cr

  my $cell = Kubernetes::Comb::SVG::Cell->from_cr( $cr, group_label => $key );

Builds one cell from a custom resource: a hash in CR shape or an object
answering C<TO_JSON>. C<group_label> is the label key for L</group>. Reads
C<metadata.name>, C<metadata.namespace>, C<metadata.labels>, C<spec.class>,
C<spec.enabled>, C<spec.dependsOn>, C<status.phase>, C<status.conditions>,
C<status.endpoints> and C<status.upstream>; everything else is ignored.

L</dependencies> and L</missing> stay empty, since one cell alone cannot
resolve them; use L</cells_from> for a set. Croaks with
C<Comb without metadata.name> when there is no name (a missing, empty or
non-string one) -- it is the only error; any other odd shape is read as absent.

=cut

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

=method cells_from

  my @cells = Kubernetes::Comb::SVG::Cell->cells_from( $input, group_label => $key );

Returns the cells of a whole set, in input order. C<$input> is an array
reference of custom resources, a C<List> hash with C<items>, one custom
resource (a hash without C<items>), or an object answering C<TO_JSON> that
turns into one of these; C<undef> gives the empty list. Options are those of
L</from_cr>. Croaks like L</from_cr> on an element without a name. Of several
custom resources with one L</id> the first is kept.

Then every C<spec.dependsOn> entry is resolved over the set into
L</dependencies> and L</missing>:

=over

=item * C<namespace/name> is the cell with exactly that L</id>.

=item * A bare C<name> is the cell of that name in the dependent's own
namespace (without namespace: the cell of that name without one), else the
only cell of that name in the whole set.

=item * No match, or several equally good ones, makes the entry
L</missing>.

=back

=cut

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

=seealso

=over

=item * L<Kubernetes::Comb::SVG>

=back

=cut
