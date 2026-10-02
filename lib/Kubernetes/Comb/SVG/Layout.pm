package Kubernetes::Comb::SVG::Layout;
# ABSTRACT: Places cells in groups, dependency rows and a honeycomb

use Moo;
use Types::Common::Numeric qw( PositiveInt PositiveNum );
use Types::Standard qw( ArrayRef Object );
use namespace::autoclean;

our $VERSION = '0.001';

has cells => ( is => 'ro', isa => ArrayRef[Object], default => sub { [] } );

has columns => ( is => 'ro', isa => PositiveInt, default => 6 );

has size => ( is => 'ro', isa => PositiveNum, default => 56 );

#### Geometry, all derived from size

# Pointy-top hexagon: flat sides left and right, a corner at top and bottom.
sub hex_width { sqrt(3) * $_[0]->size }

sub hex_height { 2 * $_[0]->size }

# Air between the sides of two neighbouring hexagons.
sub gap { $_[0]->size / 7 }

# Centre to centre inside a row.
sub step_x { $_[0]->hex_width + $_[0]->gap }

# Centre to centre between two rows: the same distance as inside a row, seen
# along the diagonal, so the gap is the same on all six sides.
sub step_y { $_[0]->step_x * sqrt(3) / 2 }

# Band above a group that holds its heading; the baseline sits inside it.
sub heading_height { $_[0]->size * 0.6 }

sub heading_baseline { $_[0]->size * 0.4 }

# Between the lowest hexagon of a group and the heading band of the next.
sub group_gap { $_[0]->size * 0.6 }

#### Layout

sub layout {
  my ( $self ) = @_;
  my $cells = $self->_unique_cells;
  my $deps  = $self->_dependencies($cells);
  my $depth = $self->_depths($deps);

  my ( %by_group, $unnamed );
  for my $cell (@$cells) {
    my $group = $cell->group;
    push @{ defined $group ? $by_group{$group} ||= [] : $unnamed ||= [] }, $cell;
  }
  my @groups = map { [ $_, $by_group{$_} ] } sort keys %by_group;
  push @groups, [ undef, $unnamed ] if $unnamed;
  my $headings = @groups > 1 || ( @groups && defined $groups[0][0] );

  my $radius = $self->size;
  my ( @placed, @placed_groups );
  my ( $width, $top ) = ( 0, 0 );
  for my $entry (@groups) {
    my ( $name, $members ) = @$entry;
    $top += $self->group_gap if @placed_groups;
    my $comb_top = $top + ( $headings ? $self->heading_height : 0 );
    my @rows = $self->_rows( $members, $depth );
    for my $row ( 0 .. $#rows ) {
      my $shift = $row % 2 ? $self->step_x / 2 : 0;
      for my $column ( 0 .. $#{ $rows[$row] } ) {
        my $cell = $rows[$row][$column];
        my $x = $shift + $self->hex_width / 2 + $column * $self->step_x;
        my $right = $x + $self->hex_width / 2;
        $width = $right if $right > $width;
        push @placed, {
          id     => $cell->id,
          name   => $cell->name,
          group  => $name,
          depth  => $depth->{ $cell->id },
          row    => $row,
          column => $column,
          x      => $self->_round($x),
          y      => $self->_round( $comb_top + $radius + $row * $self->step_y )
        };
      }
    }
    my $bottom = $comb_top + $self->hex_height + $#rows * $self->step_y;
    push @placed_groups, {
      name    => $name,
      heading => $headings
        ? { x => 0, y => $self->_round( $top + $self->heading_baseline ) }
        : undef,
      y       => $self->_round($top),
      height  => $self->_round( $bottom - $top )
    };
    $top = $bottom;
  }

  my @edges;
  for my $id ( sort keys %$deps ) {
    push @edges, map { { from => $id, to => $_ } }
      sort grep { $_ ne $id } @{ $deps->{$id} };
  }

  return {
    width  => $self->_round($width),
    height => $self->_round($top),
    groups => \@placed_groups,
    cells  => \@placed,
    edges  => \@edges
  };
}

# The cells with an id, the first of each id.
sub _unique_cells {
  my ( $self ) = @_;
  my %seen;
  return [ grep { defined $_->id && !$seen{ $_->id }++ } @{ $self->cells } ];
}

# id => ids of the cells it depends on, only those in the picture.
sub _dependencies {
  my ( $self, $cells ) = @_;
  my %known = map { $_->id => 1 } @$cells;
  my %deps;
  for my $cell (@$cells) {
    my %seen;
    $deps{ $cell->id } = [
      grep { defined && $known{$_} && !$seen{$_}++ } @{ $cell->dependencies || [] }
    ];
  }
  return \%deps;
}

# id => depth. Tarjan's strongly connected components with an explicit stack,
# so neither a cycle nor a long chain can loop or exhaust the call stack. A
# component is complete only after everything it depends on, so its depth is
# known the moment it is closed; the cells of a cycle get the same one.
sub _depths {
  my ( $self, $deps ) = @_;
  my ( %index, %low, %on_stack, %depth, @stack );
  my $counter = 0;
  for my $root ( sort keys %$deps ) {
    next if defined $index{$root};
    my @work = ( [ $root, 0 ] );
    while (@work) {
      my $frame = $work[-1];
      my $id    = $frame->[0];
      unless ( defined $index{$id} ) {
        $index{$id} = $low{$id} = $counter++;
        push @stack, $id;
        $on_stack{$id} = 1;
      }
      my $descend;
      while ( $frame->[1] < @{ $deps->{$id} } ) {
        my $dep = $deps->{$id}[ $frame->[1]++ ];
        unless ( defined $index{$dep} ) {
          $descend = $dep;
          last;
        }
        $low{$id} = $index{$dep} if $on_stack{$dep} && $index{$dep} < $low{$id};
      }
      if ( defined $descend ) {
        push @work, [ $descend, 0 ];
        next;
      }
      if ( $low{$id} == $index{$id} ) {
        my ( @members, %member );
        while (@stack) {
          my $member = pop @stack;
          delete $on_stack{$member};
          $member{$member} = 1;
          push @members, $member;
          last if $member eq $id;
        }
        my $level = 0;
        for my $dep ( map { @{ $deps->{$_} } } @members ) {
          next if $member{$dep};
          $level = $depth{$dep} + 1 if $depth{$dep} >= $level;
        }
        $depth{$_} = $level for @members;
      }
      pop @work;
      next unless @work;
      my $parent = $work[-1][0];
      $low{$parent} = $low{$id} if $low{$id} < $low{$parent};
    }
  }
  return \%depth;
}

# The drawn rows of one group: one depth after the other, each sorted by
# name and cut into rows of at most `columns` cells.
sub _rows {
  my ( $self, $cells, $depth ) = @_;
  my %by_depth;
  push @{ $by_depth{ $depth->{ $_->id } } }, $_ for @$cells;
  my @rows;
  for my $level ( sort { $a <=> $b } keys %by_depth ) {
    my @sorted = sort { $a->name cmp $b->name || $a->id cmp $b->id }
      @{ $by_depth{$level} };
    push @rows, [ splice @sorted, 0, $self->columns ] while @sorted;
  }
  return @rows;
}

# Two decimals, as a number: the same on every platform, and no '-0'.
sub _round {
  my ( $self, $value ) = @_;
  return sprintf( '%.2f', $value ) + 0;
}

1;

=head1 SYNOPSIS

  use Kubernetes::Comb::SVG::Layout;

  my $layout = Kubernetes::Comb::SVG::Layout->new(
    cells   => \@cells,
    columns => 6,
    size    => 56
  )->layout;

  for my $cell ( @{ $layout->{cells} } ) {
    # $cell->{id}, $cell->{x}, $cell->{y}, $cell->{row}, $cell->{column}
  }

=head1 DESCRIPTION

Places cells in a honeycomb and returns plain data. It knows neither the
custom resource nor SVG: a cell is anything answering C<id>, C<name>,
C<group> and C<dependencies>, as L<Kubernetes::Comb::SVG::Cell> does.

Groups are stacked top to bottom in name order, the cells without a group
last. Inside a group a cell sits in the row of its dependency depth, which is
computed over all cells; the cells of a dependency cycle share a row. Rows
are sorted by name, wrap at L</columns>, and every second one is shifted by
half a cell.

=attr cells

ArrayRef of cells. Of several with one C<id> the first is kept.

=attr columns

Cells per row before a row wraps. Default C<6>.

=attr size

Radius of a hexagon, centre to corner. Default C<56>.

=method layout

  my $layout = $self->layout;

Returns a hash:

  {
    width  => 149.49,
    height => 685.86,
    groups => [
      { name => 'alpha', heading => { x => 0, y => 22.4 }, y => 0, height => 236.53 },
      ...
    ],
    cells => [
      { id => 'ns/db', name => 'db', group => 'alpha', depth => 0,
        row => 0, column => 0, x => 48.5, y => 89.6 },
      ...
    ],
    edges => [ { from => 'ns/api', to => 'ns/db' }, ... ]
  }

C<x> and C<y> of a cell are the centre of its hexagon. C<row> and C<column>
count inside the group, C<depth> over the whole picture. Cells are listed
group by group, row by row. A group's C<name> is C<undef> for the cells
without one; C<y> and C<height> span the group including its heading.
C<heading> is the left end of the baseline of the group's heading, or
C<undef> when the only group is the unnamed one. C<edges> go from a cell to a cell it depends on,
both by C<id>; a cell depending on itself gives no edge. All coordinates are
rounded to two decimals; the content starts at C<0,0>.

=method hex_width

=method hex_height

Extent of one pointy-top hexagon of radius L</size>.

=method gap

Air between two neighbouring hexagons.

=method step_x

=method step_y

Distance between the centres of two neighbours in a row, and between two
rows.

=method heading_height

=method heading_baseline

=method group_gap

Room above a group for its heading, the baseline inside that room, and the
space between two groups.

=seealso

=over

=item * L<Kubernetes::Comb::SVG>

=item * L<Kubernetes::Comb::SVG::Cell>

=back

=cut
