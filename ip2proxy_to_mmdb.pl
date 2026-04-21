#!/usr/bin/perl
# =============================================================================
#  ip2proxy_to_mmdb.pl  —  IP2Proxy CSV → MaxMind MMDB Universal Converter
#  Supports: PX8, PX9, PX10, PX11, PX12 (LITE & Commercial)
#
#  Usage:
#    perl ip2proxy_to_mmdb.pl [options]
#
#  Options:
#    --input  <file>    Input CSV  (default: auto-detect from current dir)
#    --output <file>    Output MMDB (default: <input_basename>.mmdb)
#    --version <PXn>    Force version: PX8 PX9 PX10 PX11 PX12
#                       (default: auto-detect from filename)
#    --no-country       Skip country_name (saves space)
#    --help
#
#  Examples:
#    perl ip2proxy_to_mmdb.pl --input IP2PROXY-LITE-PX11.CSV
#    perl ip2proxy_to_mmdb.pl --input myfile.csv --version PX10 --output out.mmdb
# =============================================================================

use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case);
use File::Basename qw(basename);
use Text::CSV;
use Math::BigInt try => 'GMP,Pari';
use Net::Works::Address;
use Net::Works::Network;
use MaxMind::DB::Writer::Tree;

# ── CLI 参数 ──────────────────────────────────────────────────────────────────
my ($opt_input, $opt_output, $opt_version, $opt_no_country, $opt_help);
GetOptions(
    'input=s'    => \$opt_input,
    'output=s'   => \$opt_output,
    'version=s'  => \$opt_version,
    'no-country' => \$opt_no_country,
    'help'       => \$opt_help,
) or die usage();

print usage() and exit 0 if $opt_help;

# ── 版本字段定义 ──────────────────────────────────────────────────────────────
# 每个版本在 CSV 中 col[0]=ip_from  col[1]=ip_to  col[2..N]=数据字段
# field_def: [ col_index, field_name, mmdb_type ]
#   mmdb_type: utf8_string | uint32 | uint16 | boolean
#
# 如果你的 CSV 列顺序不同，只需调整 col_index 即可。
# -----------------------------------------------------------------------------

my %SCHEMAS = (

    # ── PX8 ─────────────────────────────────────────────────────────────────
    # ip_from, ip_to, proxy_type, country_code, country_name,
    # region_name, city_name, isp, domain, usage_type, asn, last_seen, threat
    PX8 => [
        [ 2,  'proxy_type',   'utf8_string' ],
        [ 3,  'country_code', 'utf8_string' ],
        [ 4,  'country_name', 'utf8_string' ],
        [ 5,  'region_name',  'utf8_string' ],
        [ 6,  'city_name',    'utf8_string' ],
        [ 7,  'isp',          'utf8_string' ],
        [ 8,  'domain',       'utf8_string' ],
        [ 9,  'usage_type',   'utf8_string' ],
        [ 10, 'asn',          'utf8_string' ],
        [ 11, 'last_seen',    'uint32'      ],
        [ 12, 'threat',       'utf8_string' ],
    ],

    # ── PX9 ─────────────────────────────────────────────────────────────────
    # PX8 + provider
    PX9 => [
        [ 2,  'proxy_type',   'utf8_string' ],
        [ 3,  'country_code', 'utf8_string' ],
        [ 4,  'country_name', 'utf8_string' ],
        [ 5,  'region_name',  'utf8_string' ],
        [ 6,  'city_name',    'utf8_string' ],
        [ 7,  'isp',          'utf8_string' ],
        [ 8,  'domain',       'utf8_string' ],
        [ 9,  'usage_type',   'utf8_string' ],
        [ 10, 'asn',          'utf8_string' ],
        [ 11, 'last_seen',    'uint32'      ],
        [ 12, 'threat',       'utf8_string' ],
        [ 13, 'provider',     'utf8_string' ],
    ],

    # ── PX10 ────────────────────────────────────────────────────────────────
    # PX9 + fraud_score
    PX10 => [
        [ 2,  'proxy_type',   'utf8_string' ],
        [ 3,  'country_code', 'utf8_string' ],
        [ 4,  'country_name', 'utf8_string' ],
        [ 5,  'region_name',  'utf8_string' ],
        [ 6,  'city_name',    'utf8_string' ],
        [ 7,  'isp',          'utf8_string' ],
        [ 8,  'domain',       'utf8_string' ],
        [ 9,  'usage_type',   'utf8_string' ],
        [ 10, 'asn',          'utf8_string' ],
        [ 11, 'last_seen',    'uint32'      ],
        [ 12, 'threat',       'utf8_string' ],
        [ 13, 'provider',     'utf8_string' ],
        [ 14, 'fraud_score',  'uint32'      ],
    ],

    # ── PX11 ────────────────────────────────────────────────────────────────
    # PX10 + residential
    PX11 => [
        [ 2,  'proxy_type',   'utf8_string' ],
        [ 3,  'country_code', 'utf8_string' ],
        [ 4,  'country_name', 'utf8_string' ],
        [ 5,  'region_name',  'utf8_string' ],
        [ 6,  'city_name',    'utf8_string' ],
        [ 7,  'isp',          'utf8_string' ],
        [ 8,  'domain',       'utf8_string' ],
        [ 9,  'usage_type',   'utf8_string' ],
        [ 10, 'asn',          'utf8_string' ],
        [ 11, 'last_seen',    'uint32'      ],
        [ 12, 'threat',       'utf8_string' ],
        [ 13, 'provider',     'utf8_string' ],
        [ 14, 'fraud_score',  'uint32'      ],
        [ 15, 'residential',  'utf8_string' ],
    ],

    # ── PX12 ────────────────────────────────────────────────────────────────
    # PX11 + as_name (autonomous system full name)
    PX12 => [
        [ 2,  'proxy_type',   'utf8_string' ],
        [ 3,  'country_code', 'utf8_string' ],
        [ 4,  'country_name', 'utf8_string' ],
        [ 5,  'region_name',  'utf8_string' ],
        [ 6,  'city_name',    'utf8_string' ],
        [ 7,  'isp',          'utf8_string' ],
        [ 8,  'domain',       'utf8_string' ],
        [ 9,  'usage_type',   'utf8_string' ],
        [ 10, 'asn',          'utf8_string' ],
        [ 11, 'last_seen',    'uint32'      ],
        [ 12, 'threat',       'utf8_string' ],
        [ 13, 'provider',     'utf8_string' ],
        [ 14, 'fraud_score',  'uint32'      ],
        [ 15, 'residential',  'utf8_string' ],
        [ 16, 'as_name',      'utf8_string' ],
    ],
);

# ── 自动检测输入文件 ──────────────────────────────────────────────────────────
unless ($opt_input) {
    my @candidates = sort glob("IP2PROXY*.CSV IP2Proxy*.csv");
    die "❌ 未找到 CSV 文件，请用 --input 指定。\n" unless @candidates;
    $opt_input = $candidates[0];
    warn "📂 自动选择文件: $opt_input\n";
}

die "❌ 找不到文件: $opt_input\n" unless -f $opt_input;

# ── 自动检测版本 ──────────────────────────────────────────────────────────────
unless ($opt_version) {
    my $basename = uc(basename($opt_input));
    if ($basename =~ /-(PX\d+)/i) {
        $opt_version = uc($1);
    } else {
        die "❌ 无法从文件名中识别版本，请用 --version PX11 等方式指定。\n";
    }
}

$opt_version = uc($opt_version);
die "❌ 不支持的版本: $opt_version\n支持: " . join(', ', sort keys %SCHEMAS) . "\n"
    unless exists $SCHEMAS{$opt_version};

# ── 输出路径 ──────────────────────────────────────────────────────────────────
unless ($opt_output) {
    (my $base = $opt_input) =~ s/\.[^.]+$//;
    $opt_output = "$base.mmdb";
}

# ── 字段过滤（--no-country） ──────────────────────────────────────────────────
my @schema = @{ $SCHEMAS{$opt_version} };
if ($opt_no_country) {
    @schema = grep { $_->[1] ne 'country_name' } @schema;
}

# ── 构建 MMDB 类型表 ──────────────────────────────────────────────────────────
my %types = (is_proxy => 'uint32');
for my $f (@schema) {
    $types{ $f->[1] } = $f->[2];
}

print banner($opt_version, $opt_input, $opt_output, \@schema);

my $tree = MaxMind::DB::Writer::Tree->new(
    ip_version            => 6,
    record_size           => 28,
    database_type         => "IP2Proxy-$opt_version",
    languages             => ['en'],
    description           => { en => "IP2Proxy $opt_version (converted by ip2proxy_to_mmdb.pl)" },
    map_key_type_callback => sub { $types{ $_[0] } },
);

# ── CSV 读取 ──────────────────────────────────────────────────────────────────
my $csv = Text::CSV->new({ binary => 1, auto_diag => 0 });
open my $fh, '<:encoding(utf8)', $opt_input
    or die "❌ 无法打开 $opt_input: $!\n";

# 读取并显示 CSV 表头（用于验证列顺序）
my $header_row = $csv->getline($fh);
if ($header_row) {
    print "📋 CSV 列顺序确认:\n";
    for my $i (0 .. $#$header_row) {
        printf "   [%02d] %s\n", $i, $header_row->[$i];
    }
    print "\n";
}

# ── 主循环 ────────────────────────────────────────────────────────────────────
my ($count, $skipped) = (0, 0);
my $t0 = time();

while (my $row = $csv->getline($fh)) {
    my ($ip_from, $ip_to) = ($row->[0], $row->[1]);
    next unless $ip_from && $ip_to;

    # IP 版本判断（纯数字比较，避免 BigInt 开销）
    my $version = ($ip_from <= 4_294_967_295) ? 4 : 6;

    my ($from_addr, $to_addr);
    eval {
        if ($version == 4) {
            $from_addr = Net::Works::Address->new_from_integer(integer => int($ip_from), version => 4);
            $to_addr   = Net::Works::Address->new_from_integer(integer => int($ip_to),   version => 4);
        } else {
            $from_addr = Net::Works::Address->new_from_integer(integer => Math::BigInt->new($ip_from), version => 6);
            $to_addr   = Net::Works::Address->new_from_integer(integer => Math::BigInt->new($ip_to),   version => 6);
        }
    };
    if ($@ || !$from_addr || !$to_addr) { $skipped++; next }

    # 构建数据记录
    my %data = (is_proxy => 1);
    for my $f (@schema) {
        my ($col, $name, $type) = @$f;
        my $val = $row->[$col] // '';
        next if $val eq '' || $val eq '-';
        if ($type eq 'uint32' || $type eq 'uint16') {
            $val = int($val) if $val =~ /^\d+$/;
            next unless $val =~ /^\d+$/;
        }
        $data{$name} = $val;
    }

    eval {
        my @nets = Net::Works::Network->range_as_subnets($from_addr, $to_addr);
        $tree->insert_network($_, \%data) for @nets;
    };
    if ($@) { $skipped++; next }

    $count++;
    if ($count % 100_000 == 0) {
        my $elapsed = time() - $t0 || 1;
        printf "📊 %d 条 | %.1f 条/秒 | 跳过 %d\n",
            $count, $count / $elapsed, $skipped;
    }
}
close $fh;

# ── 写出 MMDB ─────────────────────────────────────────────────────────────────
print "\n💾 写入 $opt_output ...\n";
open my $out_fh, '>:raw', $opt_output
    or die "❌ 写入失败: $!\n";
$tree->write_tree($out_fh);
close $out_fh;

my $elapsed = time() - $t0 || 1;
my $size_mb = -s $opt_output;
$size_mb = defined $size_mb ? sprintf("%.1f MB", $size_mb / 1_048_576) : '?';

print <<"END_REPORT";

╔══════════════════════════════════════════╗
║              转换完成 ✅                 ║
╠══════════════════════════════════════════╣
║  版本   : $opt_version
║  写入   : $opt_output ($size_mb)
║  成功   : $count 条
║  跳过   : $skipped 条
║  耗时   : ${elapsed}s
╚══════════════════════════════════════════╝
END_REPORT

# ── 工具函数 ──────────────────────────────────────────────────────────────────
sub usage {
    return <<'USAGE';
用法: perl ip2proxy_to_mmdb.pl [选项]

  --input  <file>     输入 CSV 文件 (默认自动检测)
  --output <file>     输出 MMDB 文件 (默认 <input>.mmdb)
  --version <PXn>     强制指定版本: PX8 PX9 PX10 PX11 PX12
  --no-country        省略 country_name 字段（节省空间）
  --help              显示帮助

示例:
  perl ip2proxy_to_mmdb.pl --input IP2PROXY-LITE-PX11.CSV
  perl ip2proxy_to_mmdb.pl --input data.csv --version PX10 --output proxy.mmdb
USAGE
}

sub banner {
    my ($ver, $in, $out, $schema_ref) = @_;
    my $fields = join(', ', map { $_->[1] } @$schema_ref);
    return <<"BANNER";
╔══════════════════════════════════════════╗
║   IP2Proxy → MMDB  Universal Converter  ║
╠══════════════════════════════════════════╣
║  版本   : $ver
║  输入   : $in
║  输出   : $out
║  字段   : $fields
╚══════════════════════════════════════════╝

🚀 开始构建...

BANNER
}