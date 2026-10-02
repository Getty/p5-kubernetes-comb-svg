package Kubernetes::Comb::SVG;
# ABSTRACT: Render Kubernetes::Comb custom resources as an SVG honeycomb

use Moo;
use Carp qw( carp );
use Types::Common::Numeric qw( PositiveInt PositiveNum );
use Types::Standard qw( Any ArrayRef Bool CodeRef HashRef Maybe Object Str );
use Kubernetes::Comb::SVG::Cell;
use Kubernetes::Comb::SVG::Layout;
use namespace::autoclean;

our $VERSION = '0.001';

has combs => ( is => 'ro', isa => Any, required => 1 );

has title => ( is => 'ro', isa => Str, default => 'Combs' );

has group_label => ( is => 'ro', isa => Maybe[Str] );

has columns => ( is => 'ro', isa => PositiveInt, default => 6 );

has size => ( is => 'ro', isa => PositiveNum, default => 56 );

has edges => ( is => 'ro', isa => Bool, default => 1 );

has legend => ( is => 'ro', isa => Bool, default => 1 );

has link => ( is => 'ro', isa => Maybe[CodeRef] );

has theme => ( is => 'ro', isa => HashRef, default => sub { {} } );

has cells => ( is => 'lazy', isa => ArrayRef[Object], init_arg => undef );

sub _build_cells {
  my ( $self ) = @_;
  return [ $self->cell_class->cells_from( $self->combs, group_label => $self->group_label ) ];
}

has _layouter => ( is => 'lazy', isa => Object, init_arg => undef );

sub _build__layouter {
  my ( $self ) = @_;
  return $self->layout_class->new(
    cells   => $self->cells,
    columns => $self->columns,
    size    => $self->size
  );
}

sub cell_class { 'Kubernetes::Comb::SVG::Cell' }

sub layout_class { 'Kubernetes::Comb::SVG::Layout' }

#### Phases and colours

sub phases {
  my ( $self ) = @_;
  return ( $self->cell_class->known_phases, 'Unknown' );
}

# Per phase the stroke colour in light and in dark mode; the fill is the same
# colour at a low opacity over the panel, so text keeps its contrast whatever
# colour a theme brings.
sub _default_colours {
  return {
    Running     => [ '#1a7f37', '#3fb950' ],
    Pending     => [ '#bf8700', '#e3b341' ],
    Blocked     => [ '#bc4c00', '#fb8f44' ],
    NeedsConfig => [ '#8250df', '#a371f7' ],
    Disabled    => [ '#8c959f', '#6e7681' ],
    Error       => [ '#cf222e', '#f85149' ],
    Unknown     => [ '#475569', '#94a3b8' ]
  };
}

sub _base_colours {
  return (
    [ bg     => '#ffffff', '#0d1117' ],
    [ border => '#d0d7de', '#30363d' ],
    [ fg     => '#1f2328', '#e6edf3' ],
    [ muted  => '#59636e', '#9198a1' ],
    [ edge   => '#57606a', '#9198a1' ]
  );
}

# A theme value is used only when it is plain colour syntax: #hex, a colour
# name, or rgb()/hsl() over a strict character set. Anything else is ignored.
sub _theme_colour {
  my ( $self, $phase ) = @_;
  my $value = $self->theme->{$phase};
  return if !defined $value || ref $value;
  return $value if $value =~ /\A#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\z/;
  return $value if $value =~ /\A[a-zA-Z]{1,32}\z/;
  return $value if $value =~ m{\A(?:rgb|hsl)a?\([0-9a-zA-Z%., /-]{1,64}\)\z}i;
  return;
}

sub _var { '--comb-'.lc $_[1] }

sub _style {
  my ( $self ) = @_;
  my $r       = $self->size;
  my $colours = $self->_default_colours;
  my ( @light, @dark );
  for my $base ( $self->_base_colours ) {
    push @light, $self->_var( $base->[0] ).':'.$base->[1];
    push @dark,  $self->_var( $base->[0] ).':'.$base->[2];
  }
  for my $phase ( $self->phases ) {
    my $theme = $self->_theme_colour($phase);
    push @light, $self->_var($phase).':'.( defined $theme ? $theme : $colours->{$phase}[0] );
    push @dark,  $self->_var($phase).':'.( defined $theme ? $theme : $colours->{$phase}[1] );
  }
  push @light, '--comb-tint:.13', '--comb-tint-muted:.06';
  push @dark,  '--comb-tint:.2',  '--comb-tint-muted:.09';

  my $s = '.comb-svg';
  my @css = (
    $s.'{'.join( ';', @light )
      .';font-family:system-ui,-apple-system,Segoe UI,Roboto,Helvetica Neue,Arial,sans-serif}',
    '@media (prefers-color-scheme:dark){'.$s.'{'.join( ';', @dark ).'}}',
    $s.' .panel{fill:var(--comb-bg);stroke:var(--comb-border);stroke-width:1}',
    $s.' text{fill:var(--comb-fg)}',
    $s.' .heading{font-size:'.$self->_n( $self->_title_font ).'px;font-weight:600}',
    $s.' .group-name{font-size:'.$self->_n( $self->_group_font )
      .'px;font-weight:600;fill:var(--comb-muted)}',
    $s.' .group-rule{stroke:var(--comb-border);stroke-width:1}',
    $s.' .hex{fill:var(--comb-unknown);fill-opacity:var(--comb-tint);stroke:var(--comb-unknown);stroke-width:'
      .$self->_n( $r * 0.03 ).';stroke-linejoin:round}',
    ( map {
      $s.' .phase-'.$_.' .hex{fill:var('.$self->_var($_).');stroke:var('.$self->_var($_).')}'
    } $self->phases ),
    $s.' .borrowed .hex{stroke-dasharray:'.$self->_n( $r * 0.11 ).' '.$self->_n( $r * 0.08 ).'}',
    $s.' .disabled .hex{fill-opacity:var(--comb-tint-muted);stroke-opacity:.55}',
    $s.' .comb text{text-anchor:middle}',
    $s.' .name{font-size:'.$self->_n( $self->_name_font ).'px;font-weight:500}',
    $s.' .phase{font-size:'.$self->_n( $self->_phase_font ).'px;fill:var(--comb-muted)}',
    $s.' .upstream{font-size:'.$self->_n( $self->_upstream_font )
      .'px;font-style:italic;fill:var(--comb-muted)}',
    $s.' .disabled text{fill:var(--comb-muted);fill-opacity:.8}',
    $s.' .dep{fill:none;stroke:var(--comb-edge);stroke-opacity:.5;stroke-width:'
      .$self->_n( $r * 0.025 ).';stroke-linecap:round;pointer-events:none}',
    $s.' .arrow{fill:var(--comb-edge);fill-opacity:.5}',
    $s.' a{cursor:pointer;text-decoration:none}',
    $s.' .legend text{font-size:'.$self->_n( $self->_legend_font ).'px;fill:var(--comb-muted)}',
    $s.' .legend .hex{stroke-width:'.$self->_n( $r * 0.02 ).'}',
    $s.' .legend .count{font-weight:600;fill:var(--comb-fg)}'
  );
  return $self->_el( 'style', [], $self->_text( join( "\n", @css ) ) );
}

#### Measures, all derived from size

sub _pad { $_[0]->size * 0.45 }

sub _title_font { $_[0]->size * 0.34 }

sub _title_band { $_[0]->size * 0.75 }

sub _group_font { $_[0]->size * 0.2 }

sub _name_font { $_[0]->size * 0.22 }

sub _phase_font { $_[0]->size * 0.17 }

sub _upstream_font { $_[0]->size * 0.15 }

sub _legend_font { $_[0]->size * 0.19 }

sub _legend_swatch { $_[0]->size * 0.15 }

sub _legend_row { $_[0]->size * 0.44 }

sub _legend_gap { $_[0]->size * 0.5 }

# Air kept between a name and the two sides of its hexagon.
sub _name_pad { $_[0]->size * 0.14 }

sub _arrow { $_[0]->size * 0.16 }

# Text is not measured, it is estimated: this share of the font size per
# character. Good enough for a system sans, and the same on every machine.
sub _char_width { 0.59 }

sub _text_width {
  my ( $self, $text, $font ) = @_;
  return length( $text ) * $font * $self->_char_width;
}

# Cuts a text to what fits into $width at $font, with an ellipsis.
sub _fit {
  my ( $self, $text, $font, $width ) = @_;
  my $max = int( $width / ( $font * $self->_char_width ) );
  $max = 1 if $max < 1;
  return $text if length $text <= $max;
  return substr( $text, 0, $max - 1 )."\x{2026}";
}

#### Escaping

# Text content. Drops what XML 1.0 cannot carry, escapes the five special
# characters, and writes everything outside ASCII as a character reference,
# so the document is plain ASCII whatever the input was.
sub _text {
  my ( $self, $value ) = @_;
  return '' if !defined $value || ref $value;
  $value = ''.$value;
  $value =~ s/[^\x09\x0A\x0D\x20-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]//g;
  $value =~ s/&/&amp;/g;
  $value =~ s/</&lt;/g;
  $value =~ s/>/&gt;/g;
  $value =~ s/"/&quot;/g;
  $value =~ s/'/&#39;/g;
  $value =~ s/([\x0D\x7F-\x{10FFFF}])/'&#'.ord($1).';'/ge;
  return $value;
}

# Attribute value: as text, and tab and newline as references too, so they
# survive attribute value normalisation.
sub _attr {
  my ( $self, $value ) = @_;
  $value = $self->_text($value);
  $value =~ s/([\x09\x0A])/'&#'.ord($1).';'/ge;
  return $value;
}

# One element. Attributes are name/value pairs in the order given, every
# value escaped here; $content is markup already and undef closes the tag.
sub _el {
  my ( $self, $name, $attrs, $content ) = @_;
  my @pairs = @$attrs;
  my $tag   = '<'.$name;
  while (@pairs) {
    my ( $key, $value ) = splice @pairs, 0, 2;
    $tag .= ' '.$key.'="'.$self->_attr($value).'"';
  }
  return defined $content ? $tag.'>'.$content.'</'.$name.'>' : $tag.'/>';
}

# Two decimals, as a number: the same on every platform, and no '-0'.
sub _n {
  my ( $self, $value ) = @_;
  return sprintf( '%.2f', $value ) + 0;
}

#### Render

sub render {
  my ( $self ) = @_;
  my $layout = $self->_layouter->layout;
  my $pad    = $self->_pad;
  my %cell   = map { $_->id => $_ } @{ $self->cells };
  my @placed = grep { $cell{ $_->{id} } } @{ $layout->{cells} };

  my %count;
  $count{ $cell{ $_->{id} }->phase }++ for @placed;
  my @occurring = grep { $count{$_} } $self->phases;

  my @legend = $self->legend
    ? map { { phase => $_, count => $count{$_}, width => $self->_legend_item_width( $_, $count{$_} ) } }
      @occurring
    : ();
  my $content = $layout->{width};
  for my $width (
    $self->_text_width( $self->title, $self->_title_font ),
    ( map { $_->{width} } @legend ),
    ( map { $self->_text_width( $_->{name}, $self->_group_font ) }
      grep { defined $_->{name} } @{ $layout->{groups} } )
  ) {
    $content = $width if $width > $content;
  }
  my @legend_rows = $self->_legend_rows( \@legend, $content );

  my $ox     = $pad;
  my $oy     = $pad + $self->_title_band;
  my $bottom = $oy + $layout->{height};
  my $legend_top = $bottom + $self->_legend_gap;
  $bottom = $legend_top + @legend_rows * $self->_legend_row - $self->_legend_row / 4
    if @legend_rows;
  my $width  = $content + 2 * $pad;
  my $height = $bottom + $pad;

  my $summary = ( @placed == 1 ? '1 Comb' : scalar(@placed).' Combs' )
    .( @occurring ? ': '.join( ', ', map { $count{$_}.' '.$_ } @occurring ) : '' );

  my %at = map { $_->{id} => [ $_->{x} + $ox, $_->{y} + $oy ] } @placed;

  my @out = (
    $self->_el( 'title', [ id => 'comb-title' ], $self->_text( $self->title ) ),
    $self->_el( 'desc',  [ id => 'comb-desc' ],  $self->_text($summary) ),
    $self->_style,
    $self->_el( 'defs', [], $self->_marker ),
    $self->_el( 'rect', [
      class  => 'panel',
      x      => 0.5,
      y      => 0.5,
      width  => $self->_n( $width - 1 ),
      height => $self->_n( $height - 1 ),
      rx     => $self->_n( $self->size * 0.22 )
    ] ),
    $self->_el( 'text', [
      class => 'heading',
      x     => $self->_n($ox),
      y     => $self->_n( $pad + $self->_title_font * 0.8 )
    ], $self->_text( $self->title ) )
  );

  push @out, map { $self->_group( $_, $ox, $oy, $content ) }
    grep { $_->{heading} } @{ $layout->{groups} };

  if ( $self->edges ) {
    my @paths = map { $self->_edge( $_, $at{ $_->{from} }, $at{ $_->{to} } ) }
      grep { $at{ $_->{from} } && $at{ $_->{to} } } @{ $layout->{edges} };
    push @out, $self->_el( 'g', [ class => 'deps' ], join( '', @paths ) ) if @paths;
  }

  push @out, map { $self->_comb( $cell{ $_->{id} }, @{ $at{ $_->{id} } } ) } @placed;

  push @out, $self->_legend( \@legend_rows, $ox, $legend_top ) if @legend_rows;

  return $self->_el( 'svg', [
    xmlns             => 'http://www.w3.org/2000/svg',
    viewBox           => '0 0 '.$self->_n($width).' '.$self->_n($height),
    role              => 'img',
    class             => 'comb-svg',
    'aria-labelledby' => 'comb-title comb-desc'
  ], "\n".join( "\n", @out )."\n" )."\n";
}

sub _marker {
  my ( $self ) = @_;
  my $arrow = $self->_n( $self->_arrow );
  return $self->_el( 'marker', [
    id           => 'comb-arrow',
    viewBox      => '0 0 10 10',
    refX         => 0,
    refY         => 5,
    markerWidth  => $arrow,
    markerHeight => $arrow,
    markerUnits  => 'userSpaceOnUse',
    orient       => 'auto'
  ], $self->_el( 'path', [ class => 'arrow', d => 'M0 1L10 5L0 9z' ] ) );
}

# The heading of a group: its name and a faint rule to the right of it. The
# unnamed group among named ones gets the rule alone.
sub _group {
  my ( $self, $group, $ox, $oy, $content ) = @_;
  my $x    = $group->{heading}{x} + $ox;
  my $y    = $group->{heading}{y} + $oy;
  my $font = $self->_group_font;
  my ( $text, $from ) = ( '', $x );
  if ( defined $group->{name} ) {
    $text = $self->_el( 'text', [
      class => 'group-name',
      x     => $self->_n($x),
      y     => $self->_n($y)
    ], $self->_text( $group->{name} ) );
    $from = $x + $self->_text_width( $group->{name}, $font ) + $font * 0.8;
  }
  my $to   = $ox + $content;
  my $rule = $to - $from > $font
    ? $self->_el( 'line', [
        class => 'group-rule',
        x1    => $self->_n($from),
        y1    => $self->_n( $y - $font * 0.35 ),
        x2    => $self->_n($to),
        y2    => $self->_n( $y - $font * 0.35 )
      ] )
    : '';
  return $self->_el( 'g', [
    class => 'group',
    defined $group->{name} ? ( 'data-group' => $group->{name} ) : ()
  ], $text.$rule );
}

sub _hexagon {
  my ( $self, $x, $y, $radius ) = @_;
  my $half = $radius * sqrt(3) / 2;
  my @points = (
    [ $x,         $y - $radius ],
    [ $x + $half, $y - $radius / 2 ],
    [ $x + $half, $y + $radius / 2 ],
    [ $x,         $y + $radius ],
    [ $x - $half, $y + $radius / 2 ],
    [ $x - $half, $y - $radius / 2 ]
  );
  return $self->_el( 'polygon', [
    class  => 'hex',
    points => join( ' ', map { $self->_n( $_->[0] ).','.$self->_n( $_->[1] ) } @points )
  ] );
}

sub _tooltip {
  my ( $self, $cell ) = @_;
  my @lines = ( $cell->id );
  push @lines, 'namespace: '.$cell->namespace if defined $cell->namespace;
  push @lines, 'class: '.$cell->class         if defined $cell->class;
  push @lines, 'phase: '.$cell->phase
    .( $cell->phase eq 'Unknown' && defined $cell->raw_phase ? ' ('.$cell->raw_phase.')' : '' );
  push @lines, 'message: '.$cell->message
    if defined $cell->message && $cell->phase ne 'Running';
  push @lines, map { 'endpoint: '.$_->{name}.( defined $_->{port} ? ' '.$_->{port} : '' ) }
    @{ $cell->endpoints };
  if ( $cell->borrowed ) {
    push @lines, 'upstream: '.( defined $cell->upstream_context ? $cell->upstream_context : 'yes' );
    push @lines, 'via: '.join( ', ', @{ $cell->upstream_via } ) if @{ $cell->upstream_via };
  }
  push @lines, 'missing: '.join( ', ', @{ $cell->missing } ) if @{ $cell->missing };
  return join( "\n", @lines );
}

# The href for a cell, or undef: what the link callback answers, when it is
# relative or http(s) and carries neither whitespace nor control characters.
sub _href {
  my ( $self, $cell ) = @_;
  return unless $self->link;
  my $href = eval { $self->link->($cell) };
  if ( my $error = $@ ) {
    carp __PACKAGE__.'->render: link callback died for '.$cell->id.': '.$error;
    return;
  }
  return if !defined $href || ref $href || !length $href;
  return if $href =~ /[\x00-\x20\x7F]/;
  return $href if $href =~ m{\Ahttps?://}i;
  return if $href =~ m{\A[^/?#]*:};
  return $href;
}

sub _comb {
  my ( $self, $cell, $x, $y ) = @_;
  my $r        = $self->size;
  my $borrowed = $cell->borrowed;
  my $disabled = $cell->phase eq 'Disabled';
  my $width    = $self->_layouter->hex_width;
  my $shift    = $borrowed ? -0.1 * $r : 0;

  my @parts = (
    $self->_el( 'title', [], $self->_text( $self->_tooltip($cell) ) ),
    $self->_hexagon( $x, $y, $r ),
    $self->_el( 'text', [
      class => 'name',
      x     => $self->_n($x),
      y     => $self->_n( $y + $shift - 0.07 * $r )
    ], $self->_text( $self->_fit( $cell->name, $self->_name_font, $width - 2 * $self->_name_pad ) ) ),
    $self->_el( 'text', [
      class => 'phase',
      x     => $self->_n($x),
      y     => $self->_n( $y + $shift + 0.23 * $r )
    ], $self->_text( $cell->phase ) )
  );
  push @parts, $self->_el( 'text', [
    class => 'upstream',
    x     => $self->_n($x),
    y     => $self->_n( $y + $shift + 0.48 * $r )
  ], $self->_text( $self->_fit(
    defined $cell->upstream_context ? 'from '.$cell->upstream_context : 'borrowed',
    $self->_upstream_font, $width * 0.8
  ) ) ) if $borrowed;

  my $group = $self->_el( 'g', [
    class => join( ' ', 'comb', 'phase-'.$cell->phase,
      $borrowed ? 'borrowed' : (), $disabled ? 'disabled' : () ),
    'data-name'  => $cell->name,
    'data-id'    => $cell->id,
    'data-phase' => $cell->phase
  ], join( '', @parts ) );

  my $href = $self->_href($cell);
  return defined $href ? $self->_el( 'a', [ href => $href ], $group ) : $group;
}

# One dependency, dependent to dependency, drawn between the label-free
# corner regions of its two ends: the name, phase and upstream lines fill the
# middle band of a hexagon, the regions towards its top and bottom corner are
# free. The line starts well inside the dependent and its arrowhead ends
# inside the dependency.
#
# Across rows it is a straight line from the corner region facing the
# dependency into the corner region facing the dependent. Inside one row it
# is a bow through the corner regions of the cells it passes: above the row
# when it runs left to right, below when it runs right to left, so the two
# edges of a cycle never share a line.
sub _edge {
  my ( $self, $edge, $from, $to ) = @_;
  my $r = $self->size;
  my ( $dx, $dy ) = ( $to->[0] - $from->[0], $to->[1] - $from->[1] );
  return () if abs($dx) < 0.01 && abs($dy) < 0.01;

  my ( @a, @b, @via );
  if ( abs($dy) < 0.01 ) {
    my $along = $dx > 0 ? 1 : -1;
    my $side  = -$along;
    my $steps = abs($dx) / $self->_layouter->step_x;
    $steps = 3 if $steps > 3;
    @a   = ( $from->[0] + $along * $r * 0.3, $from->[1] + $side * $r * 0.5 );
    @b   = ( $to->[0] - $along * $r * 0.35,  $to->[1] + $side * $r * 0.55 );
    @via = ( ( $a[0] + $b[0] ) / 2, $from->[1] + $side * $r * ( 0.9 + 0.15 * $steps ) );
  }
  else {
    my $side = $dy > 0 ? 1 : -1;
    @a = ( $from->[0] + $self->_clamp( $dx * 0.3, $r * 0.2 ), $from->[1] + $side * $r * 0.46 );
    @b = ( $to->[0] - $self->_clamp( $dx * 0.3, $r * 0.3 ),   $to->[1] - $side * $r * 0.6 );
  }

  # @b is the tip of the arrowhead; the marker draws it beyond the end of the
  # path, so the path stops one arrowhead short, along its last direction.
  my @last  = @via ? @via : @a;
  my $angle = atan2( $b[1] - $last[1], $b[0] - $last[0] );
  my @end   = ( $b[0] - cos($angle) * $self->_arrow, $b[1] - sin($angle) * $self->_arrow );

  my $d = 'M'.$self->_n( $a[0] ).' '.$self->_n( $a[1] )
    .( @via ? 'Q'.$self->_n( $via[0] ).' '.$self->_n( $via[1] ).' ' : 'L' )
    .$self->_n( $end[0] ).' '.$self->_n( $end[1] );
  return $self->_el( 'path', [
    class        => 'dep',
    'data-from'  => $edge->{from},
    'data-to'    => $edge->{to},
    d            => $d,
    'marker-end' => 'url(#comb-arrow)'
  ] );
}

sub _clamp {
  my ( $self, $value, $limit ) = @_;
  return $value > $limit ? $limit : $value < -$limit ? -$limit : $value;
}

#### Legend

sub _legend_item_width {
  my ( $self, $phase, $count ) = @_;
  return $self->_legend_swatch * 2.6
    + $self->_text_width( $phase.' '.$count, $self->_legend_font );
}

# Fills rows of at most $width, at least one item each.
sub _legend_rows {
  my ( $self, $items, $width ) = @_;
  my $gap = $self->size * 0.35;
  my ( @rows, $used );
  for my $item (@$items) {
    if ( !@rows || $used + $gap + $item->{width} > $width ) {
      push @rows, [];
      $used = -$gap;
    }
    $item->{x} = $used + $gap;
    $used = $item->{x} + $item->{width};
    push @{ $rows[-1] }, $item;
  }
  return @rows;
}

sub _legend {
  my ( $self, $rows, $ox, $top ) = @_;
  my $swatch = $self->_legend_swatch;
  my @items;
  for my $row ( 0 .. $#$rows ) {
    my $y = $top + $row * $self->_legend_row + $swatch;
    for my $item ( @{ $rows->[$row] } ) {
      my $x = $ox + $item->{x} + $swatch;
      push @items, $self->_el( 'g', [
        class        => 'legend-item phase-'.$item->{phase},
        'data-phase' => $item->{phase},
        'data-count' => $item->{count}
      ], $self->_hexagon( $x, $y, $swatch )
        .$self->_el( 'text', [
          x => $self->_n( $x + $swatch * 1.6 ),
          y => $self->_n( $y + $self->_legend_font * 0.35 )
        ], $self->_text( $item->{phase} ).' '
          .$self->_el( 'tspan', [ class => 'count' ], $self->_text( $item->{count} ) ) ) );
    }
  }
  return $self->_el( 'g', [ class => 'legend' ], join( '', @items ) );
}

1;

=head1 SYNOPSIS

  use Kubernetes::Comb::SVG;

  my $svg = Kubernetes::Comb::SVG->new(
    combs       => \@combs,
    title       => 'Lab',
    group_label => 'app.kubernetes.io/part-of'
  )->render;

=head1 DESCRIPTION

Draws a set of L<Kubernetes::Comb> custom resources as one self-contained SVG
document: a honeycomb with one hexagon per Comb, coloured by its phase, with
the dependencies drawn between them. Data in, string out: no cluster access,
no script and no external reference in the picture, and the same input gives
the same bytes.

=attr combs

The custom resources: an array reference of hashes in CR shape or of objects
answering C<TO_JSON>, or a C<List> hash with C<items>. Required.

=attr title

The C<< <title> >> of the picture and its heading. Default C<Combs>.

=attr group_label

Label key whose value names a cell's group. No default.

=attr columns

Cells per row before a row wraps. Default C<6>.

=attr size

Radius of a hexagon in SVG units. Default C<56>.

=attr edges

Draw the dependency edges. Default true.

=attr legend

Draw the legend. Default true.

=attr link

Coderef, called with a L<Kubernetes::Comb::SVG::Cell>; returns the href the
cell links to, or C<undef>. Only a relative or C<http:>/C<https:> href is
used.

=attr theme

Hash C<< phase => colour >>, merged over the built-in colours.

=attr cells

The L<Kubernetes::Comb::SVG::Cell> objects read from L</combs>. Not a
constructor argument.

=method render

  my $svg = $self->render;

Returns the SVG document as a string of ASCII characters.

=method phases

The known phases in their fixed order, then C<Unknown>.

=method cell_class

=method layout_class

The classes that read the custom resources and place the cells.

=seealso

=over

=item * L<Kubernetes::Comb::SVG::Cell>

=item * L<Kubernetes::Comb::SVG::Layout>

=back

=cut
