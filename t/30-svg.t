#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON::MaybeXS;
use Path::Tiny;
use XML::LibXML;
use XML::LibXML::XPathContext;

use Kubernetes::Comb::SVG;

# The picture, SPEC 6 to 8: the SVG is parsed with a real XML parser and every
# assertion looks at elements and attributes.

my $SVG  = 'Kubernetes::Comb::SVG';
my $data = path(__FILE__)->parent->child( 'data', 'svg' );
my $json = JSON::MaybeXS->new( utf8 => 1 );
my $SIZE = 56;

sub fixture { $json->decode( $data->child( $_[0].'.json' )->slurp_raw ) }

# A fixture name or the combs themselves in, the parsed picture out.
sub picture {
  my ( $combs, %opt ) = @_;
  $combs = fixture($combs) unless ref $combs;
  return parse( $SVG->new( combs => $combs, %opt )->render );
}

sub parse {
  my ( $svg ) = @_;
  my $xpc = XML::LibXML::XPathContext->new( XML::LibXML->load_xml( string => $svg ) );
  $xpc->registerNs( s => 'http://www.w3.org/2000/svg' );
  return $xpc;
}

sub has_class { 'contains(concat(" ",@class," ")," '.$_[0].' ")' }

# Cells only: the legend swatches are polygon.hex as well, but never g.comb.
my $COMB = 'g[ '.has_class('comb').' ]';

sub combs { $_[0]->findnodes( '//s:'.$COMB ) }

sub comb {
  my ( $xpc, $name ) = @_;
  my ( $node ) = grep { $_->getAttribute('data-name') eq $name } combs($xpc);
  return $node;
}

sub comb_by_id {
  my ( $xpc, $id ) = @_;
  my ( $node ) = grep { $_->getAttribute('data-id') eq $id } combs($xpc);
  return $node;
}

sub classes { +{ map { $_ => 1 } split ' ', $_[0]->getAttribute('class') } }

# XPath from any node, with the svg prefix known
sub xp {
  my ( $node ) = @_;
  return $node if $node->isa("XML::LibXML::XPathContext");
  my $xpc = XML::LibXML::XPathContext->new($node);
  $xpc->registerNs( s => "http://www.w3.org/2000/svg" );
  return $xpc;
}

sub child { my ( $node, $path ) = @_; xp($node)->findnodes($path) }

sub val { my ( $node, $path ) = @_; xp($node)->findvalue($path) }

# The text of a cell's line, by class
sub line { my ( $node, $class ) = @_; join '', map { $_->textContent } child( $node, 's:text[ '.has_class($class).' ]' ) }

# Centre of a hexagon: the first point is the top corner, one radius above it
sub centre {
  my ( $node, $size ) = @_;
  my ( $x, $y ) = val( $node, q{s:polygon/@points} ) =~ /\A(\S+),(\S+)/;
  return ( $x, $y + ( $size || $SIZE ) );
}

sub tooltip { [ split /\n/, val( $_[0], "s:title" ) ] }

sub count { scalar @{ [ xp($_[0])->findnodes( $_[1] ) ] } }

sub style_text { $_[0]->findvalue('//s:style') }

sub view_box { [ split ' ', $_[0]->findvalue('/s:svg/@viewBox') ] }

subtest 'root, title, desc, style, defs' => sub {
  my $xpc = picture( 'phases', title => 'Lab' );
  my $root = $xpc->findnodes('/s:svg')->get_node(1);
  is( $root->getAttribute('xmlns'), 'http://www.w3.org/2000/svg', 'xmlns' );
  is( $root->getAttribute('role'), 'img', 'role img' );
  is( $root->getAttribute('aria-labelledby'), 'comb-title comb-desc', 'labelled by title and desc' );
  ok( $root->hasAttribute('class') && classes($root)->{'comb-svg'}, 'svg.comb-svg' );
  like( $root->getAttribute('viewBox'), qr/\A0 0 [\d.]+ [\d.]+\z/, 'viewBox' );
  ok( !$root->hasAttribute('width') && !$root->hasAttribute('height'), 'no fixed pixel size' );

  is( $xpc->findvalue('/s:svg/s:title[@id="comb-title"]'), 'Lab', 'title element, id comb-title' );
  is( count( $xpc, '/s:svg/s:desc[@id="comb-desc"]' ), 1, 'desc element, id comb-desc' );
  is( $xpc->findvalue('/s:svg/s:text[@class="heading"]'), 'Lab', 'text.heading carries the title' );
  is( $xpc->findvalue('/s:svg/s:rect[@class="panel"]/@class'), 'panel', 'rect.panel' );
  is( count( $xpc, '/s:svg/s:defs/s:marker[@id="comb-arrow"]' ), 1, 'arrow marker in defs' );

  is( count( $xpc, '//s:style' ), 1, 'exactly one style element' );
  my $css = style_text($xpc);
  for my $var (qw( running pending blocked needsconfig disabled error unknown bg fg )) {
    like( $css, qr/--comb-\Q$var\E:#/, '--comb-'.$var.' custom property' );
  }
  my @media = $css =~ /(\@media \(prefers-color-scheme:dark\))/g;
  is( scalar @media, 1, 'one prefers-color-scheme dark block' );
};

subtest 'default title' => sub {
  my $xpc = picture('no-status');
  is( $xpc->findvalue('/s:svg/s:title'), 'Combs', 'default title is Combs' );
};

subtest 'desc: the summary' => sub {
  is( picture('phases')->findvalue('/s:svg/s:desc'),
    '6 Combs: 1 Running, 1 Pending, 1 Blocked, 1 NeedsConfig, 1 Disabled, 1 Error',
    'fixed phase order' );
  is( picture('no-status')->findvalue('/s:svg/s:desc'), '1 Comb: 1 Unknown', 'singular, Unknown counted' );
  is( picture( [] )->findvalue('/s:svg/s:desc'), '0 Combs', 'empty is 0 Combs' );
  my @mixed = map { { metadata => { name => 'n'.$_ }, status => { phase => $_ < 5 ? 'Running' : 'Error' } } } 1 .. 6;
  push @mixed, { metadata => { name => 'u' }, status => { phase => 'Blocked' } }, { metadata => { name => 'v' } };
  is( picture( \@mixed )->findvalue('/s:svg/s:desc'),
    '8 Combs: 4 Running, 1 Blocked, 2 Error, 1 Unknown',
    'counts per phase in the fixed order, Unknown last' );
};

subtest 'every phase' => sub {
  my $xpc = picture('phases');
  my @nodes = combs($xpc);
  is( scalar @nodes, 6, 'one g.comb per cell' );
  for my $phase (qw( Running Pending Blocked NeedsConfig Disabled Error )) {
    my $node = comb( $xpc, lc $phase );
    ok( $node, $phase.': cell found' );
    ok( classes($node)->{ 'phase-'.$phase }, $phase.': class phase-'.$phase );
    is( $node->getAttribute('data-phase'), $phase, $phase.': data-phase' );
    is( line( $node, 'phase' ), $phase, $phase.': phase as text, not by colour alone' );
    is( count( $node, 's:polygon[ '.has_class('hex').' ]' ), 1, $phase.': one hexagon' );
    is( line( $node, 'name' ), lc $phase, $phase.': name text' );
    is( count( $node, 's:text[ '.has_class('upstream').' ]' ), 0, $phase.': no upstream line' );
  }
  my @points = map { val( $_, q{s:polygon/@points} ) } @nodes;
  is( scalar( () = $points[0] =~ /,/g ), 6, 'a hexagon has six points' );
  my %id = map { $_->getAttribute('data-id') => 1 } @nodes;
  is( scalar keys %id, 6, 'six distinct data-id' );
};

subtest 'unknown phase' => sub {
  my $node = comb( picture('unknown-phase'), 'odd' );
  ok( classes($node)->{'phase-Unknown'}, 'class phase-Unknown' );
  is( $node->getAttribute('data-phase'), 'Unknown', 'data-phase is Unknown' );
  is( line( $node, 'phase' ), 'Unknown', 'phase text is Unknown' );
  ok( ( grep { $_ eq 'phase: Unknown (Frobnicating)' } @{ tooltip($node) } ),
    'tooltip keeps the original phase text' );
};

subtest 'missing status' => sub {
  my $node = comb( picture('no-status'), 'bare' );
  ok( classes($node)->{'phase-Unknown'}, 'class phase-Unknown' );
  is( line( $node, 'phase' ), 'Unknown', 'phase text Unknown' );
  is_deeply( tooltip($node), [ 'bare', 'phase: Unknown' ], 'tooltip: no original phase, no message' );
  ok( !classes($node)->{borrowed} && !classes($node)->{disabled}, 'neither borrowed nor disabled' );
};

subtest 'disabled' => sub {
  my $xpc = picture('disabled');
  my $off = comb( $xpc, 'off' );
  ok( classes($off)->{disabled}, 'spec.enabled false: class disabled' );
  ok( classes($off)->{'phase-Disabled'}, 'and phase-Disabled' );
  is( $off->getAttribute('data-phase'), 'Disabled', 'data-phase Disabled whatever status says' );
  is( line( $off, 'phase' ), 'Disabled', 'phase text' );
  my $on = comb( $xpc, 'on' );
  ok( !classes($on)->{disabled}, 'the enabled one is not disabled' );
  ok( classes( comb( picture('phases'), 'disabled' ) )->{disabled}, 'status phase Disabled is muted too' );
};

subtest 'borrowed' => sub {
  my $xpc = picture('borrowed');
  my $with = comb( $xpc, 'with-context' );
  ok( classes($with)->{borrowed}, 'borrowed class' );
  is( line( $with, 'upstream' ), 'from prod', 'upstream line names the context' );
  ok( ( grep { $_ eq 'upstream: prod' } @{ tooltip($with) } ), 'tooltip: upstream context' );
  ok( ( grep { $_ eq 'via: prod' } @{ tooltip($with) } ), 'tooltip: via' );

  my $without = comb( $xpc, 'no-context' );
  ok( classes($without)->{borrowed}, 'borrowed without context' );
  is( line( $without, 'upstream' ), 'borrowed', 'upstream line says borrowed' );
  ok( ( grep { $_ eq 'upstream: yes' } @{ tooltip($without) } ), 'tooltip: upstream yes' );

  my $own = comb( $xpc, 'own' );
  ok( !classes($own)->{borrowed}, 'own cell is not borrowed' );
  is( count( $own, 's:text[ '.has_class('upstream').' ]' ), 0, 'no text.upstream unless borrowed' );
};

subtest 'tooltip lines' => sub {
  my $xpc = picture('tooltip');
  is_deeply(
    tooltip( comb( $xpc, 'api' ) ),
    [
      'lab/api', 'namespace: lab', 'class: My::Api', 'phase: Blocked',
      'message: waiting for db', 'endpoint: http 8080', 'endpoint: admin',
      'upstream: prod', 'via: prod, edge', 'missing: gone'
    ],
    'id, namespace, class, phase, message, endpoints, upstream, via, missing'
  );
  is_deeply( tooltip( comb( $xpc, 'db' ) ), [ 'lab/db', 'namespace: lab', 'phase: Unknown' ], 'a bare cell' );
};

subtest 'groups' => sub {
  my $xpc = picture( 'groups', group_label => 'tier' );
  my @groups = $xpc->findnodes( '//s:g[ '.has_class('group').' ]' );
  is( scalar @groups, 3, 'two named groups and the unnamed one' );
  is_deeply(
    [ map { $_->hasAttribute('data-group') ? $_->getAttribute('data-group') : undef } @groups ],
    [ 'backend', 'frontend', undef ],
    'name order, the unnamed group last, without data-group'
  );
  is( val( $groups[0], q{s:text[@class="group-name"]} ), 'backend', 'heading text' );
  is( val( $groups[1], q{s:text[@class="group-name"]} ), 'frontend', 'heading text' );
  is( count( $groups[0], 's:line[@class="group-rule"]' ), 1, 'named group has a rule' );
  is( count( $groups[2], 's:text' ), 0, 'unnamed group has no text' );

  my %y = map { $_->getAttribute('data-name') => ( centre($_) )[1] } combs($xpc);
  is_deeply( [ sort keys %y ], [qw( alpha beta loose zeta )], 'every cell drawn once' );
  cmp_ok( $y{beta}, '<', $y{alpha}, 'backend above frontend' );
  cmp_ok( $y{alpha}, '<', $y{loose}, 'unnamed group below the named ones' );
  is( $y{beta}, $y{zeta}, 'cells of one group and depth share a row' );

  my $plain = picture( 'groups' );
  is( count( $plain, '//s:g[ '.has_class('group').' ]' ), 0, 'without group_label there is no heading' );
  is( count( $plain, '//s:'.$COMB ), 4, 'all cells still drawn' );
};

subtest 'depth rows' => sub {
  my $xpc = picture('chain');
  my %y = map { $_->getAttribute('data-name') => ( centre($_) )[1] } combs($xpc);
  cmp_ok( $y{db}, '<', $y{api}, 'the dependency is above its dependent' );
  cmp_ok( $y{api}, '<', $y{web}, 'one row per depth' );
};

subtest 'wrap at columns' => sub {
  my $xpc = picture( 'wrap', columns => 2 );
  my %row;
  $row{ ( centre($_) )[1] }++ for combs($xpc);
  is_deeply( [ map { $row{$_} } sort { $a <=> $b } keys %row ], [ 2, 2, 1 ], 'five cells at columns 2: 2, 2, 1' );
  my %default;
  $default{ ( centre($_) )[1] }++ for combs( picture('wrap') );
  is_deeply( [ values %default ], [5], 'default columns keep five cells in one row' );
};

subtest 'cycle' => sub {
  my $xpc;
  is( eval { $xpc = picture('cycle'); 1 }, 1, 'a cycle and a self-dependency render' ) or diag $@;
  is( count( $xpc, '//s:'.$COMB ), 3, 'three cells' );
  my ( $ya, $yb ) = map { ( centre( comb( $xpc, $_ ) ) )[1] } qw( a b );
  is( $ya, $yb, 'the cells of a cycle share a row' );
  my %edge = map { $_->getAttribute('data-from').'>'.$_->getAttribute('data-to') => 1 }
    $xpc->findnodes('//s:path[@class="dep"]');
  ok( $edge{'a>b'} && $edge{'b>a'}, 'both edges of the cycle are drawn' );
};

subtest 'cycle edges bow to opposite sides' => sub {
  my $xpc = picture( [
    { metadata => { name => 'a' }, spec => { dependsOn => ['c'] } },
    { metadata => { name => 'b' } },
    { metadata => { name => 'c' }, spec => { dependsOn => ['a'] } }
  ] );
  my $row = ( centre( comb( $xpc, 'a' ) ) )[1];
  my %bow;
  for my $path ( $xpc->findnodes('//s:path[@class="dep"]') ) {
    my ( $start, $via, $end ) = $path->getAttribute('d') =~ /\AM\S+ (\S+)Q\S+ (\S+) \S+ (\S+)\z/;
    $bow{ $path->getAttribute('data-from') } = [ map { $_ - $row } $start, $via, $end ];
  }
  is_deeply( [ sort keys %bow ], [ 'a', 'c' ], 'both edges of a cycle are bows' );
  is( scalar( grep { $_ < -$SIZE * 0.4 } @{ $bow{a} } ), 3, 'left to right bows above the labels' );
  is( scalar( grep { $_ > $SIZE * 0.4 } @{ $bow{c} } ), 3, 'right to left bows below the labels' );
};

subtest 'unknown dependency' => sub {
  my $xpc = picture('unknown-dep');
  is( count( $xpc, '//s:'.$COMB ), 1, 'a picture' );
  is( count( $xpc, '//s:path[@class="dep"]' ), 0, 'no edge to a name that is not there' );
  is( count( $xpc, '//s:g[@class="deps"]' ), 0, 'and no empty g.deps' );
  ok( ( grep { $_ eq 'missing: ghost' } @{ tooltip( comb( $xpc, 'api' ) ) } ), 'listed as missing in the tooltip' );
};

subtest 'identity is namespace/name' => sub {
  my $xpc = picture('same-name');
  is( count( $xpc, '//s:'.$COMB ), 3, 'same name in two namespaces: two cells' );
  is_deeply(
    [ sort map { $_->getAttribute('data-id') } combs($xpc) ],
    [ 'dev/api', 'dev/db', 'prod/db' ],
    'data-id is namespace/name'
  );
  is( count( $xpc, '//s:'.$COMB.'[@data-name="db"]' ), 2, 'data-name is the plain name' );
  my @edges = $xpc->findnodes('//s:path[@class="dep"]');
  is( scalar @edges, 1, 'one edge' );
  is( $edges[0]->getAttribute('data-from'), 'dev/api', 'from the dependent' );
  is( $edges[0]->getAttribute('data-to'), 'dev/db', 'to the dependency in its own namespace' );
};

subtest 'edges' => sub {
  my $xpc = picture('chain');
  my @edges = $xpc->findnodes('//s:g[@class="deps"]/s:path[@class="dep"]');
  is_deeply(
    [ sort map { $_->getAttribute('data-from').'>'.$_->getAttribute('data-to') } @edges ],
    [ 'api>db', 'web>api' ],
    'from is the dependent, to the dependency'
  );
  is( $_->getAttribute('marker-end'), 'url(#comb-arrow)', 'arrowhead at the dependency' ) for $edges[0];
  like( $_->getAttribute('d'), qr/\AM/, 'path data' ) for $edges[0];
  for my $name ( 'chain', 'cycle' ) {
    my $pic = picture($name);
    my $n   = count( $pic, '//s:path[@class="dep"]' );
    is(
      count( $pic, '//s:g[@class="deps"]/s:path[@class="dep"]/following-sibling::*[1][self::s:circle][@class="dep-start"]' ),
      $n, $name.': every edge is followed by its start dot'
    );
    is( count( $pic, '//s:circle[@class="dep-start"]' ), $n, $name.': and there is no other start dot' );
  }
  is( count( $xpc, '//s:g[@class="deps"]/following-sibling::s:'.$COMB ), 3, 'edges come before the cells' );
  is( count( $xpc, '//s:'.$COMB.'/preceding-sibling::s:g[@class="deps"]' ), 1, "all of them in one g.deps" );

  my $off = picture( 'chain', edges => 0 );
  is( count( $off, '//s:path[@class="dep"]' ), 0, 'edges => 0: no path.dep' );
  is( count( $off, '//s:g[@class="deps"]' ), 0, 'edges => 0: no g.deps' );
  is( count( $off, '//s:'.$COMB ), 3, 'edges => 0: cells still drawn' );

  is( count( picture('phases'), '//s:g[@class="deps"]' ), 0, 'no dependencies: no g.deps' );
};

subtest 'legend' => sub {
  my $xpc = picture('phases');
  my @items = $xpc->findnodes('//s:g[@class="legend"]/s:g[ '.has_class('legend-item').' ]');
  is( scalar @items, 6, 'one item per phase that occurs' );
  is_deeply(
    [ map { $_->getAttribute('data-phase') } @items ],
    [qw( Running Pending Blocked NeedsConfig Disabled Error )],
    'fixed phase order'
  );
  ok( classes( $items[0] )->{'phase-Running'}, 'item carries the phase class' );
  is( $items[0]->getAttribute('data-count'), 1, 'data-count' );
  is( count( $items[0], 's:polygon[ '.has_class('hex').' ]' ), 1, 'legend swatch is a hexagon' );
  like( $items[0]->textContent, qr/Running\s+1/, 'item text: phase and count' );
  is( count( $xpc, '//s:'.$COMB ), 6, 'swatches are not cells' );

  my $some = picture( [
    ( map { { metadata => { name => 'r'.$_ }, status => { phase => 'Running' } } } 1 .. 3 ),
    { metadata => { name => 'x' }, status => { phase => 'Error' } },
    { metadata => { name => 'u' } }
  ] );
  my %count = map { $_->getAttribute('data-phase') => $_->getAttribute('data-count') }
    $some->findnodes('//s:g[ '.has_class('legend-item').' ]');
  is_deeply( \%count, { Running => 3, Error => 1, Unknown => 1 }, 'only phases that occur, with counts' );

  is( count( picture( 'phases', legend => 0 ), '//s:g[@class="legend"]' ), 0, 'legend => 0: no legend' );
  is( count( picture( [] ), '//s:g[@class="legend"]' ), 0, 'no cells: no legend' );
};

subtest 'long names' => sub {
  my $name = 'web-frontend-with-a-long-name';
  my $xpc  = picture( [ { metadata => { name => $name } } ] );
  my $node = comb( $xpc, $name );
  is( line( $node, 'name' ), "web-fronte\x{2026}", 'cut with an ellipsis' );
  is( $node->getAttribute('data-name'), $name, 'data-name keeps the whole name' );
  ok( ( grep { $_ eq 'default/'.$name || $_ eq $name } @{ tooltip($node) } ), 'the tooltip keeps the whole name' );
  my $short = comb( picture( [ { metadata => { name => 'db' } } ] ), 'db' );
  is( line( $short, 'name' ), 'db', 'a short name is untouched' );
};

subtest 'escaping' => sub {
  my $svg = $SVG->new( combs => fixture('hostile'), group_label => 'tier', title => '<b>"T" & \'t\'</b>' )->render;
  my $xpc;
  is( eval { $xpc = parse($svg); 1 }, 1, 'well-formed XML' ) or diag $@;
  is( count( $xpc, '//*[local-name()="script"]' ), 0, 'no script element anywhere' );
  is( count( $xpc, '//@*[starts-with(local-name(),"on")]' ), 0, 'no event handler attribute' );
  unlike( $svg, qr/<script/i, 'no literal script tag in the bytes' );
  unlike( $svg, qr/[^\x00-\x7F]/, 'plain ASCII output' );

  is_deeply(
    [ sort map { $_->getAttribute('data-name') } combs($xpc) ],
    [ sort 'ctlx', 'q"uo\'te&amp;<>', '</svg><script>alert(1)</script>' ],
    'data-name round-trips the original string (control characters dropped)'
  );
  my $evil = comb( $xpc, '</svg><script>alert(1)</script>' );
  is( $evil->getAttribute('data-id'), 'ns"\'&<>/</svg><script>alert(1)</script>', 'data-id round-trips' );
  my $tip = tooltip($evil);
  ok( ( grep { $_ eq 'namespace: ns"\'&<>' } @$tip ), 'namespace in the tooltip, verbatim' );
  ok( ( grep { $_ eq 'message: msg "quoted" & <b>bold</b> \'x\'' } @$tip ), 'message in the tooltip, verbatim' );
  ok( ( grep { $_ eq 'upstream: ctx"><script>x</script>&' } @$tip ), 'upstream context in the tooltip, verbatim' );
  is( count( $evil, '*[not(self::s:title or self::s:polygon or self::s:text)]' ), 0, 'cell has only its own children' );
  is( count( $evil, 's:text/*' ), 0, 'no element inside any text' );
  like( line( $evil, 'upstream' ), qr/\Afrom ctx">/, 'upstream line is text' );

  my @heads = $xpc->findnodes('//s:g[ '.has_class('group').' ]');
  is( $heads[0]->getAttribute('data-group'), 'grp"\'&<script>', 'data-group round-trips' );
  is( val( $heads[0], "s:text" ), 'grp"\'&<script>', 'group heading text round-trips' );

  my $odd = comb( $xpc, 'q"uo\'te&amp;<>' );
  ok( ( grep { $_ eq 'phase: Unknown (Run"ning<script>)' } @{ tooltip($odd) } ), 'raw phase escaped in the tooltip' );
  is( line( $odd, 'phase' ), 'Unknown', 'phase text is the known name' );

  my $title = '<b>"T" & \'t\'</b>';
  is( $xpc->findvalue('/s:svg/s:title'), $title, 'title option round-trips in <title>' );
  is( $xpc->findvalue('/s:svg/s:text[@class="heading"]'), $title, 'and in the heading' );

  my $ctl = comb( $xpc, 'ctlx' );
  ok( $ctl, 'control characters are dropped, the cell is drawn' );
  unlike( $svg, qr/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, 'no control character in the document' );
};

subtest 'unicode' => sub {
  my $name = "caf\x{e9}-\x{1F600}-\x{4e2d}";
  my $svg  = $SVG->new( combs => [ { metadata => { name => $name } } ] )->render;
  unlike( $svg, qr/[^\x00-\x7F]/, 'ASCII bytes, no encoding question' );
  is( ( combs( parse($svg) ) )[0]->getAttribute('data-name'), $name, 'data-name round-trips' );
};

subtest 'link' => sub {
  my $one = sub {
    my ( $href ) = @_;
    my $xpc = picture( [ { metadata => { name => 'a' } } ], link => sub { $href } );
    return $xpc;
  };
  for my $href ( 'cells/a.html', '/cells/a', '#a', '?x=1', 'a/b:c', 'http://h/p', 'https://h/p?a=1&b=2',
    'HTTPS://h/', '//h/x' ) {
    my $xpc = $one->($href);
    my @a = $xpc->findnodes('//s:a');
    is( scalar @a, 1, 'accepted: '.$href );
    is( $a[0]->getAttribute('href'), $href, '  href round-trips' ) if @a;
    is( count( $xpc, '//s:a/s:'.$COMB ), 1, '  the anchor wraps the cell' );
  }
  for my $href (
    'javascript:alert(1)', 'JavaScript:alert(1)', 'jAvAsCrIpT:alert(1)', 'data:text/html,x', 'vbscript:x',
    'mailto:a@b', 'ftp://h/x', ' https://h/', "\thttps://h/", "https://h/ x", "java\tscript:alert(1)",
    "java\nscript:alert(1)", "https://h/\x00", ''
  ) {
    my $shown = $href; $shown =~ s/([^\x20-\x7e])/sprintf '\x%02x', ord $1/ge;
    my $xpc = $one->($href);
    is( count( $xpc, '//s:a' ), 0, 'refused: "'.$shown.'"' );
    is( count( $xpc, '//s:'.$COMB ), 1, '  cell still drawn' );
  }
  is( count( $one->(undef), '//s:a' ), 0, 'undef: no anchor' );
  is( count( picture('link'), '//s:a' ), 0, 'no link option: no anchor' );

  my $xpc = picture( [ { metadata => { name => 'a' } } ], link => sub { 'x"onload="y&z<>' } );
  my ( $a ) = $xpc->findnodes('//s:a');
  is( $a->getAttribute('href'), 'x"onload="y&z<>', 'href is escaped as an attribute' );
  is( count( $xpc, '//@*[local-name()="onload"]' ), 0, 'no injected attribute' );

  my @seen;
  picture( 'link', link => sub { push @seen, $_[0]; undef } );
  is_deeply( [ map { ref $_ } @seen ], [ ('Kubernetes::Comb::SVG::Cell') x 3 ], 'callback gets the Cell' );
  is_deeply( [ sort map { $_->id } @seen ], [qw( a b c )], 'once per cell' );

  my @warn;
  my $died = do {
    local $SIG{__WARN__} = sub { push @warn, @_ };
    picture( 'link', link => sub { die "nope\n" if $_[0]->name eq 'b'; '/'.$_[0]->name } );
  };
  is( count( $died, '//s:'.$COMB ), 3, 'a dying callback still gives the picture' );
  is_deeply( [ map { $_->getAttribute('href') } $died->findnodes('//s:a') ], [ '/a', '/c' ], 'only the cell that died has no link' );
  is( scalar @warn, 1, 'one warning' );
  like( $warn[0], qr/link callback died for b: nope/, 'the warning says which cell and why' );
};

subtest 'theme' => sub {
  my $default = style_text( picture('phases') );
  like( $default, qr/--comb-running:#1a7f37/, 'default Running colour' );

  my $css = style_text( picture( 'phases', theme => { Running => '#ff00aa', Error => 'rgb(1, 2, 3)', Blocked => 'tomato' } ) );
  like( $css, qr/--comb-running:#ff00aa;/, 'a hex colour lands in the style (light)' );
  like( $css, qr/\@media \(prefers-color-scheme:dark\)\{[^}]*--comb-running:#ff00aa/, 'and in the dark block' );
  like( $css, qr/--comb-error:rgb\(1, 2, 3\)/, 'rgb() is accepted' );
  like( $css, qr/--comb-blocked:tomato/, 'a colour name is accepted' );
  like( $css, qr/--comb-pending:#bf8700/, 'other phases keep their default' );

  for my $bad (
    'red;}</style><script>x</script>', 'url(http://evil/x)', 'expression(alert(1))',
    '#ff00aa; background:url(x)', "#fff\n}", '}', 'red"', { a => 1 }
  ) {
    my $xpc = picture( 'phases', theme => { Running => $bad } );
    my $style = style_text($xpc);
    like( $style, qr/--comb-running:#1a7f37/, 'hostile theme value falls back to the default' );
    unlike( $style, qr/evil|script|expression|background/, '  and does not reach the style' );
    is( count( $xpc, '//s:style' ), 1, '  style element count unchanged' );
    is( count( $xpc, '//*[local-name()="script"]' ), 0, '  no script' );
  }

  my $xpc = picture( 'phases', theme => { Bogus => '#123456', bg => '#123456' } );
  my $style = style_text($xpc);
  unlike( $style, qr/--comb-bogus|#123456/, 'unknown key is ignored' );
  like( $style, qr/--comb-bg:#ffffff/, 'a non-phase key does not touch the base colours' );
};

subtest 'size and columns' => sub {
  my $base  = view_box( picture('wrap') );
  my $small = view_box( picture( 'wrap', size => 28 ) );
  cmp_ok( $small->[2], '<', $base->[2], 'a smaller size narrows the viewBox' );
  cmp_ok( $small->[3], '<', $base->[3], 'and lowers it' );
  my $narrow = view_box( picture( 'wrap', columns => 2 ) );
  cmp_ok( $narrow->[2], '<', $base->[2], 'fewer columns narrow the viewBox' );
  cmp_ok( $narrow->[3], '>', $base->[3], 'and make it taller' );
  my $big = comb( picture( 'wrap', size => 100 ), 'c1' );
  is( count( $big, 's:polygon' ), 1, 'cell drawn at another size' );
  my $pts = [ val( $big, q{s:polygon/@points} ) =~ /(-?[\d.]+),(-?[\d.]+)/g ];
  my @ys  = @$pts[ grep { $_ % 2 } 0 .. $#$pts ];
  my ( $min, $max ) = ( sort { $a <=> $b } @ys )[ 0, -1 ];
  is( sprintf( '%.0f', $max - $min ), 200, 'hexagon height is twice the size option' );
};

subtest 'self-contained' => sub {
  my %run = (
    hostile => [ 'hostile', link => sub { 'https://h/'.$_[0]->name =~ s/\W//gr }, group_label => 'tier' ],
    chain   => ['chain'],
    full    => [ 'tooltip', link => sub { '/x' }, theme => { Running => '#abcdef' } ],
    empty   => [ [] ]
  );
  for my $label ( sort keys %run ) {
    my ( $combs, @opt ) = @{ $run{$label} };
    my $svg = $SVG->new( combs => ref $combs ? $combs : fixture($combs), @opt )->render;
    my $xpc = parse($svg);
    is( count( $xpc, '//*[local-name()="script" or local-name()="image" or local-name()="foreignObject" or local-name()="use" or local-name()="iframe"]' ), 0, $label.': no script, image, foreignObject, use' );
    is( count( $xpc, '//s:style' ), 1, $label.': one style element' );
    is( count( $xpc, '//@*[local-name()="href" and not(parent::s:a)]' ), 0, $label.': href only on anchors' );
    my @external = grep { !m{\Ahttps?://h/} && !m{\A/x\z} } map { $_->value } $xpc->findnodes('//s:a/@href');
    is( scalar @external, 0, $label.': anchors point only where the callback said' );
    unlike( $svg, qr/xlink/i, $label.': no xlink' );
    my $css = style_text($xpc);
    unlike( $css, qr/\@import|url\(|https?:|\/\//, $label.': style has no import, url() or external reference' );
    my @urls = map { $_->value } $xpc->findnodes('//@*[contains(.,"url(")]');
    is_deeply( [ grep { $_ ne 'url(#comb-arrow)' } @urls ], [], $label.': the only url() is the arrow marker' );
    is( count( $xpc, '//@*[local-name()="src" or local-name()="data"]' ), 0, $label.': no src attribute' );
    my %id;
    $id{$_}++ for map { $_->value } $xpc->findnodes('//@id');
    is_deeply( [ sort keys %id ], [ 'comb-arrow', 'comb-desc', 'comb-title' ], $label.': a fixed set of ids' );
  }
};

subtest 'determinism' => sub {
  my @args = ( combs => fixture('tooltip'), group_label => 'tier', title => 'Lab' );
  my $first = $SVG->new(@args)->render;
  is( $first, $SVG->new(@args)->render, 'two objects, same bytes' );
  my $object = $SVG->new(@args);
  is( $object->render, $object->render, 'one object rendered twice, same bytes' );

  my $hostile = fixture('hostile');
  is( $SVG->new( combs => $hostile )->render, $SVG->new( combs => $hostile )->render, 'hostile input is stable too' );
  my $out = $first;
  unlike( $out, qr/\d{4}-\d{2}-\d{2}|\bid="[a-f0-9]{8,}/, 'no timestamp, no generated id' );

  my @cr = @{ fixture('chain') };
  my $forward  = $SVG->new( combs => [@cr] )->render;
  my $backward = $SVG->new( combs => [ reverse @cr ] )->render;
  my ( $f, $b ) = ( parse($forward), parse($backward) );
  my $place = sub { +{ map { $_->getAttribute('data-id') => join( ',', centre($_) ) } combs( $_[0] ) } };
  is_deeply( $place->($b), $place->($f), 'input order does not move any cell' );
  is( $backward, $forward, 'input order does not change the bytes' );
};

subtest 'input shapes' => sub {
  {
    package Local::CR;
    sub new { my ( $class, $cr ) = @_; bless { cr => $cr }, $class }
    sub TO_JSON { $_[0]{cr} }
  }
  my $xpc = picture( [ map { Local::CR->new($_) } @{ fixture('phases') } ] );
  is( count( $xpc, '//s:'.$COMB ), 6, 'objects answering TO_JSON' );
  is( $xpc->findvalue('/s:svg/s:desc'), picture('phases')->findvalue('/s:svg/s:desc'), 'same picture as plain hashes' );

  my $list = picture('list');
  is( count( $list, '//s:'.$COMB ), 2, 'a List hash with items' );
  is( $list->findvalue('/s:svg/s:desc'), '2 Combs: 1 Running, 1 Error', 'summary of the list' );

  my $single = picture( Local::CR->new( { metadata => { name => 'solo' } } ) );
  is( count( $single, '//s:'.$COMB ), 1, 'one object, not wrapped in an array' );
};

subtest 'empty input' => sub {
  for my $empty ( [], { kind => 'List', items => [] } ) {
    my $xpc = picture($empty);
    is( count( $xpc, '/s:svg' ), 1, 'a valid document' );
    is( count( $xpc, '//s:'.$COMB ), 0, 'no cells' );
    is( count( $xpc, '//s:g[@class="legend" or @class="deps"]' ), 0, 'no legend, no edges' );
    is( $xpc->findvalue('/s:svg/s:desc'), '0 Combs', 'desc' );
    my $box = view_box($xpc);
    ok( $box->[2] > 0 && $box->[3] > 0, 'viewBox has a positive size' );
    is( count( $xpc, '//s:style' ), 1, 'style still there' );
    is( count( $xpc, '/s:svg/s:text[@class="heading"]' ), 1, 'heading still there' );
  }
};

subtest 'a Comb without a name is an error' => sub {
  my $ok = eval { $SVG->new( combs => fixture('no-name') )->render; 1 };
  ok( !$ok, 'dies' );
  like( $@, qr/metadata\.name/, 'and says what is missing' );
  ok( !eval { $SVG->new( combs => [ {} ] )->render; 1 }, 'an empty hash is no Comb' );
};

done_testing;
