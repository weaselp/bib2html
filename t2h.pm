#!/usr/bin/perl

# based on code taken from
# https://tex.stackexchange.com/questions/44486/pixel-perfect-vertical-alignment-of-image-rendered-tex-snippets/45621#45621
# on 2014-02-10
# user contributions licensed under cc by-sa 3.0 with attribution required
#
# Further updates, Copyright (c) 2014 Peter Palfrader, under CC BY-SA 3.0

#==============================================================================
#
#   CONVERT SIMPLE PLAIN TEXT TO HTML WITH TEX MATH SNIPPETS
#
#   This program takes on standard input a simple text file containing TeX
#   arbitrary math snippets (delimited by '$'s) and produces on standard
#   output an HTML document with PNG images embedded in <IMG> tags.
#
#   This program demonstrates conversion techniques and is not intended for
#   production use.
#
#   Todd S. Lehman
#   February 2012
#

# cleaned up and hacked on by Peter Palfrader
# Copyright 2014 Peter Palfrader

use strict;
use warnings;
use Exporter;
use English;
use File::Temp;
use IPC::Run;
use Parse::RecDescent;


use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 0.01;
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw(math_to_htmlimg tex_to_html get_extra_css);
%EXPORT_TAGS = ( DEFAULT => [qw(&math_to_htmlimg tex_to_html)] );

my $extra_css = {};
my $extra_css_ctr = 0;

sub store_extra_css($) {
    my ($def) = @_;
    unless (exists $extra_css->{$def}) {
        $extra_css_ctr++;
        my $name = "t2h_style_$extra_css_ctr";
        $extra_css->{$def} = $name;
    }
    return $extra_css->{$def};
}

sub get_extra_css() {
    my @css = ();
    for my $k (keys %$extra_css) {
        my $val = $extra_css->{$k};
        push @css, ".$val { $k }";
    }
    return join("\n", @css)."\n";
}

my $TEX_TEMPLATE = '\documentclass[10pt]{article}
\pagestyle{empty}
\setlength{\topskip}{0pt}
\setlength{\parindent}{0pt}
\setlength{\abovedisplayskip}{0pt}
\setlength{\belowdisplayskip}{0pt}

\usepackage{geometry}

\usepackage{amsmath}

\newsavebox{\snippetbox}
\newlength{\snippetwidth}
\newlength{\snippetheight}
\newlength{\snippetdepth}
\newlength{\pagewidth}
\newlength{\pageheight}
\newlength{\pagemargin}

\begin{lrbox}{\snippetbox}%
$<SNIPPET>$%
\end{lrbox}

\settowidth{\snippetwidth}{\usebox{\snippetbox}}
\settoheight{\snippetheight}{\usebox{\snippetbox}}
\settodepth{\snippetdepth}{\usebox{\snippetbox}}

\setlength\pagemargin{4pt}

\setlength\pagewidth\snippetwidth
\addtolength\pagewidth\pagemargin
\addtolength\pagewidth\pagemargin

\setlength\pageheight\snippetheight
\addtolength{\pageheight}{\snippetdepth}
\addtolength\pageheight\pagemargin
\addtolength\pageheight\pagemargin

\newwrite\foo
\immediate\openout\foo=\jobname.dimensions
  \immediate\write\foo{snippetdepth = \the\snippetdepth}
  \immediate\write\foo{snippetheight = \the\snippetheight}
  \immediate\write\foo{snippetwidth = \the\snippetwidth}
  \immediate\write\foo{pagewidth = \the\pagewidth}
  \immediate\write\foo{pageheight = \the\pageheight}
  \immediate\write\foo{pagemargin = \the\pagemargin}
\closeout\foo

\geometry{paperwidth=\pagewidth,paperheight=\pageheight,margin=\pagemargin}

\begin{document}%
\usebox{\snippetbox}%
\end{document}
';
my %HTML_CACHE;

sub flat {
  map { ref $_ ? flat(@{$_}) : $_ } @_;
}

# run external command
sub run_cmd {
    #print STDERR "Running ", join(' ', flat @_), "\n";
    unless (IPC::Run::run(@_)) {
        my $cmd = join(' ', flat @_);
        my ($exit_value) = $?>>8;
        die ("Command $cmd exited with $exit_value\n");
    }
}

# round number up to the next higher multiple
sub round_up ($$) {
    my ($num, $mod) = @_;
    return $num + ($num % $mod == 0?  0 : ($mod - ($num % $mod)));
}


# fetch width and height from pnm file
sub pnm_width_height ($) {
    my ($filename) = @_;
    $filename =~ m/\.pnm$/ or die "$filename: not .pnm";

    open(PNM, '<', $filename) or die "$filename: can't read";
    my $line = <PNM>;  # Skip first line.
    do { $line = <PNM> } while $line =~ m/^#/;  # Read next line, skipping comments
    close(PNM);

    my ($width, $height) = ($line =~ m/^(\d+)\s+(\d+)$/);
    defined($width) && defined($height)
        or die "$filename: Couldn't read image size";
    return ($width, $height);
}


# compile latex snippet into htmL
sub math_to_htmlimg ($) {
    my ($tex_snippet) = @_;

    return $HTML_CACHE{$tex_snippet} if (exists $HTML_CACHE{$tex_snippet});

    my $render_antialias_bits = 4;
    my $render_oversample = 4;
    my $display_oversample = 4;
    my $oversample = $render_oversample * $display_oversample;
    my $render_dpi = 96*1.2 * 72.27/72 * $oversample;  # This is 1850.112 dpi.

    my $tmpdir = File::Temp->newdir();
    my $file = $tmpdir.'/tth';

    (my $tex_input = $TEX_TEMPLATE) =~ s{<SNIPPET>}{$tex_snippet};

    # --- Write TeX source and compile to PDF.
    open(TEX, '>', "$file.tex") and print TEX $tex_input and close(TEX)
        or die "$file.tex: can't write";

    run_cmd([
        "pdflatex",
        "-halt-on-error",
        "-output-directory=$tmpdir",
        "-output-format=pdf",
        "$file.tex"
        ], '>', '/dev/null');

    # --- Convert PDF to PNM using Ghostscript.
    run_cmd([
        "gs",
        "-q", "-dNOPAUSE", "-dBATCH",
        "-dTextAlphaBits=$render_antialias_bits",
        "-dGraphicsAlphaBits=$render_antialias_bits",
        "-r$render_dpi",
        "-sDEVICE=pnmraw",
        "-sOutputFile=$file.pnm",
        "$file.pdf"
        ]);

    my ($img_width, $img_height) = pnm_width_height("$file.pnm");


    # --- Read dimensions file written by TeX during processing.
    #
    #     Example of file contents:
    #       snippetdepth = 6.50009pt
    #       snippetheight = 13.53899pt
    #       snippetwidth = 145.4777pt
    #       pagewidth = 153.4777pt
    #       pageheight = 28.03908pt
    #       pagemargin = 4.0pt

    my $dimensions = {};
    do {
        open(DIMENSIONS, '<', "$file.dimensions")
            or die "$file.dimensions: can't read";
        while (<DIMENSIONS>) {
            if (m/^(\S+)\s+=\s+(-?[0-9\.]+)pt$/) {
                my ($value, $length) = ($1, $2);
                $length = $length / 72.27 * $render_dpi;
                $dimensions->{$value} = $length;
            } else {
                die "$file.dimensions: invalid line: $_";
            }
        }
        close(DIMENSIONS);
    };

    #foreach (keys %$dimensions) { print "# $_=$dimensions->{$_}px\n"; }
    #print "# \n";

    # --- Crop bottom, then measure how much was cropped.
    run_cmd([
        "pnmcrop",
        "-white",
        "-bottom",
        "$file.pnm"
        ], '>', "$file.bottomcrop.pnm");

    my ($img_width_bottomcrop, $img_height_bottomcrop) = pnm_width_height("$file.bottomcrop.pnm");

    my $bottomcrop = $img_height - $img_height_bottomcrop;
    #printf "# Cropping bottom:  %d pixels - %d pixels = %d pixels cropped\n",
    #    $img_height, $img_height_bottomcrop, $bottomcrop;


    # --- Crop top and sides, then measure how much was cropped from the top.
    run_cmd([
        "pnmcrop",
        "-white",
        "$file.bottomcrop.pnm"
        ], '>', "$file.crop.pnm");

    my ($cropped_img_width, $cropped_img_height) = pnm_width_height("$file.crop.pnm");

    my $topcrop = $img_height_bottomcrop - $cropped_img_height;
    #printf "# Cropping top:  %d pixels - %d pixels = %d pixels cropped\n",
    #    $img_height_bottomcrop, $cropped_img_height, $topcrop;


    # --- Pad image with specific values on all four sides, in preparation for
    #     downsampling.
    # Calculate bottom padding.
    my $snippet_depth = int($dimensions->{snippetdepth} + $dimensions->{pagemargin} + .5) - $bottomcrop;
    my $padded_snippet_depth = round_up($snippet_depth, $oversample);
    my $increase_snippet_depth = $padded_snippet_depth - $snippet_depth;
    my $bottom_padding = $increase_snippet_depth;
    #printf "# Padding snippet depth:  %d pixels + %d pixels = %d pixels\n",
    #    $snippet_depth, $increase_snippet_depth, $padded_snippet_depth;


    # --- Next calculate top padding, which depends on bottom padding.

    my $padded_img_height = round_up($cropped_img_height + $bottom_padding, $oversample);
    my $top_padding = $padded_img_height - ($cropped_img_height + $bottom_padding);
    #printf "# Padding top:  %d pixels + %d pixels = %d pixels\n",
    #    $cropped_img_height, $top_padding, $padded_img_height;


    # --- Calculate left and right side padding.  Distribute padding evenly.

    my $padded_img_width = round_up($cropped_img_width, $oversample);
    my $left_padding = int(($padded_img_width - $cropped_img_width) / 2);
    my $right_padding = ($padded_img_width - $cropped_img_width) - $left_padding + 16;
    #printf "# Padding left = $left_padding pixels\n";
    #printf "# Padding right = $right_padding pixels\n";


    # --- Pad the final image.

    run_cmd([
        "pnmpad",
        "-white",
        "-bottom=$bottom_padding",
        "-top=$top_padding",
        "-left=$left_padding",
        "-right=$right_padding",
        "$file.crop.pnm"
        ], '>', "$file.pad.pnm");


    # --- Sanity check of final size.

    my ($final_pnm_width, $final_pnm_height) = pnm_width_height("$file.pad.pnm");
    $final_pnm_width % $oversample == 0 or die "$final_pnm_width is not a multiple of $oversample";
    $final_pnm_height % $oversample == 0 or die "$final_pnm_height is not a multiple of $oversample";


    # --- Convert PNM to PNG.

    my $final_png_width  = $final_pnm_width  / $render_oversample;
    my $final_png_height = $final_pnm_height / $render_oversample;

    run_cmd(
        [qw{ppmtopgm}], '<', "$file.pad.pnm",
        # "| pamscale -reduce $render_oversample",
        '|', ['pnmscale', '-reduce', $render_oversample],
            '2>', '/dev/null',
        '|', [qw{pnmgamma .3"}],
        '|', [qw{pnmtopng -compression 9"}],
        '>', "$file.png",
            '2>', '/dev/null'
    );


    # --- Convert PNG to HTML.

    my $html_img_width  = $final_png_width  / $display_oversample;
    my $html_img_height = $final_png_height / $display_oversample;

    my $html_img_vertical_align = sprintf("%.0f", -$padded_snippet_depth / $oversample);

    (my $html_img_title = $tex_snippet) =~ s{([&<>'"])}{sprintf("&#%d;",ord($1))}eg;

    my $png_data_base64 = do {
        open(PNG, '<', "$file.png") or die "$file.png: can't open";
        binmode PNG;
        my $png_data = do { local $/; <PNG> };
        close(PNG);
        use MIME::Base64;
        MIME::Base64::encode_base64($png_data);
    };
    #$png_data_base64 =~ s/\s+//g;

    my $cssclass = store_extra_css(sprintf("vertical-align:%dpx;", $html_img_vertical_align));
    my $html = sprintf(
        '<img '.
            'width="%d" '.
            'height="%d" '.
            'class="%s" '.
            'title="%s" '.
            'alt="%s" '.
            "src=\"data:image/png;base64,\n%s\" ".
            '/>',
        $html_img_width, $html_img_height, $cssclass, $html_img_title, $html_img_title, $png_data_base64);

    $HTML_CACHE{$tex_snippet} = $html;

    # --- Clean up and return result to caller.
    return $html;
}



#------------------------------------------------------------------------------
# main control
#------------------------------------------------------------------------------
my $MARKUP_MAP = {
    #'bibitem'  => ['<a class="bibitem" id="@@TOKEN@@" href="#@@TOKEN@@">@@TOKEN@@</a><br />'],
    'textsc'   => ['<span class="fontsmallcaps">', '</span>'],
    'textbf'   => ['<strong>', '</strong>'],
    'sc'       => ['<span class="fontsmallcaps">', '</span>'],
    'emph'     => ['<em>', '</em>'],
    'em'       => ['<em>', '</em>'],
    '\\'       => "<br /><br />",
    ','        => ' ',
    ' '        => ' ',
    '/'        => '/',
    '&'        => '&amp;',
    'url'      => ['<a href="@@TOKEN@@">@@TOKEN@@</a>'],
    'newblock' => '<br />',
};
sub markup($$) {
    my $how = shift;
    my $what = shift;

    if (exists $MARKUP_MAP->{$how}) {
        my $m = $MARKUP_MAP->{$how};
        if (ref($m) eq 'ARRAY') {
            warn("missing block for $how.\n"), return "" unless defined $what;
            if (scalar @$m == 1) {
                my $r = $m->[0];
                $r =~ s/\@\@TOKEN\@\@/$what/g;
                return $r;
            } else {
                return $m->[0].$what.$m->[1];
            }
        } else {
            return $m.(defined $what ? $what : "");
        }
    } else {
        warn("Unknown latex token '\\$how'.\n");
        return $what;
    }
};

sub tex_to_html($) {
    my ($input) = @_;
    #(my $html = $input) =~ s{\$(.*?)\$}{math_to_htmlimg($1)}seg;

    #$html =~ s{([^\s<>]*<img.*?>[^\s<>]*)}
    #          {<span style="white-space:nowrap;">$1</span>}sg;

    #return $html;
    $::RD_HINT = 1;
    $::RD_ERRORS = 1;
    my $grammar = <<'    END';
        {
            use strict;
            use warnings;
        }

        exprs: expr(s) { join('', @{$item[1]}); }

        expr: mathblock
            | curlyblock
            | plaintext
            | cmd
            | specials

        mathblock: '$' /[^\$]+/ '$' { ::math_to_htmlimg($item[2]) }

        curlyblock: '{' exprs '}' { $item[2] }

        plaintext: /[^\${}\\<>&~-]+/

        specials: '---' { '&mdash;' }
                | '--'  { '&ndash;' }
                | '-'   { '-' }
                | '&'   { '&amp;' }
                | '<'   { '&lt;' }
                | '>'   { '&gt;' }
                | '~'   { '&nbsp;' }

        cmd: '\\' command curlyblock { ::markup($item[2], $item[3]); }
           | '\\' command exprs      { ::markup($item[2], $item[3]); }
           | '\\' command            { ::markup($item[2], undef); }

        command: /[a-zA-Z0-9_]+/
               | /[&,\\\/]/
               | /\s/                { " " }
    END

    return '' if $input eq '';
    $Parse::RecDescent::skip = '';
    my $parser = new Parse::RecDescent($grammar);
    my $p = $parser->exprs(\$input);
    if ($input ne '') {
      warn("Failed to convert tex to html at '$input'.\n");
      $p .= $input;
    }
    return $p;


#print <<EOT;
#<?xml version="1.0" encoding="UTF-8"?>
#<!DOCTYPE html 
# PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
# "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
#<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
#<head>
#<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
#<title></title>
#</head>
#<body>
#<p>
#$html
#</p>
#</body>
#</html>
#EOT
}

1;

# vim:et:ts=4:sw=4:softtabstop=4:
