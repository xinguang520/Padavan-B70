<?php
# ---------------------------------------------------------------
# monitor.sh - 路由器端采集器
# 输出两份内容:
#   1) /etc/storage/www/status.json  → 给 dashboard.html AJAX 用
#   2) /etc/storage/www/status.html  → 单页完整 status
# 也可以命令行跑,纯文本输出: monitor.sh text
# ---------------------------------------------------------------
$mode = isset($argv[1]) ? $argv[1] : 'json';
$PREFIX = '/etc/storage';

function cmd($cmd) {
    $out = [];
    exec($cmd . ' 2>&1', $out, $rc);
    return trim(implode("\n", $out));
}

function cmd_first($cmd) {
    $out = cmd($cmd);
    if (strpos($out, "\n") !== false) {
        $lines = explode("\n", $out);
        return trim($lines[0]);
    }
    return $out;
}

// --- CPU ---
$cpuinfo = file_get_contents('/proc/stat');
preg_match('/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/m', $cpuinfo, $m);
if ($m) {
    $total = $m[1] + $m[2] + $m[3] + $m[4];
    $idle  = $m[4];
    $cpu_pct = ($total > 0) ? round(100 * (1 - $idle / $total), 1) : 0;
} else {
    $cpu_pct = 0;
}

// --- 内存 ---
$meminfo = file_get_contents('/proc/meminfo');
preg_match('/MemTotal:\s+(\d+)/', $meminfo, $mt);
preg_match('/MemFree:\s+(\d+)/', $meminfo, $mf);
preg_match('/Buffers:\s+(\d+)/', $meminfo, $mb);
preg_match('/Cached:\s+(\d+)/',   $meminfo, $mc);
$mem_total = isset($mt[1]) ? intval($mt[1]) : 0;
$mem_free  = isset($mf[1]) ? intval($mf[1]) : 0;
$buf       = isset($mb[1]) ? intval($mb[1]) : 0;
$cached    = isset($mc[1]) ? intval($mc[1]) : 0;
$mem_used  = $mem_total - $mem_free - $buf - $cached;
$mem_pct   = $mem_total > 0 ? round(100 * $mem_used / $mem_total, 1) : 0;

// --- 磁盘(挂在 /etc/storage 的 jffs2) ---
$df = explode("\n", cmd("df -k /etc/storage | tail -1"));
if (count($df) >= 2) {
    $parts = preg_split('/\s+/', $df[0]);
    $disk_total = isset($parts[1]) ? intval($parts[1]) * 1024 : 0;
    $disk_used  = isset($parts[2]) ? intval($parts[2]) * 1024 : 0;
    $disk_pct   = isset($parts[4]) ? intval(rtrim($parts[4], '%')) : 0;
} else {
    $disk_total = $disk_used = $disk_pct = 0;
}

// --- 运行时长 + 负载 ---
$uptime_raw = cmd_first('cat /proc/uptime');
$uptime_sec = intval(explode(' ', $uptime_raw)[0]);
$uptime_str = sprintf("%d天%d小时%d分", $uptime_sec / 86400, ($uptime_sec % 86400) / 3600, ($uptime_sec % 3600) / 60);

$loadavg = cmd_first('cat /proc/loadavg');
$load_parts = explode(' ', $loadavg);

// --- WAN IP ---
$wan_ip = cmd_first("nvram get wan_ipaddr 2>/dev/null");
if (empty($wan_ip) || $wan_ip == '0.0.0.0') $wan_ip = 'N/A';

$lan_ip = cmd_first("nvram get lan_ipaddr 2>/dev/null");

// --- 服务状态 ---
function proc_status($name) {
    $pid = trim(shell_exec("pidof $name 2>/dev/null"));
    if (empty($pid)) {
        return ['status' => 'down', 'pid' => '', 'uptime' => '', 'mem' => ''];
    }
    $pid = explode(' ', $pid)[0];
    $info = shell_exec("cat /proc/$pid/stat 2>/dev/null");
    $etime = trim(shell_exec("cat /proc/$pid/stat 2>/dev/null | awk '{print \$22}'"));
    $rss = trim(shell_exec("cat /proc/$pid/status 2>/dev/null | grep VmRSS | awk '{print \$2}'"));
    $mem_kb = intval($rss);
    return [
        'status' => 'up',
        'pid' => $pid,
        'uptime' => $etime ? sprintf("%d秒", $etime / 100) : '?',
        'mem' => $mem_kb ? sprintf("%.1f MB", $mem_kb / 1024) : '?',
    ];
}

$services = [
    'aria2c'        => proc_status('aria2c'),
    'tailscaled'    => proc_status('tailscaled'),
    'clash'         => proc_status('clash'),
    'sing-box'      => proc_status('sing-box'),
    'nginx'         => proc_status('nginx'),
    'httpd'         => proc_status('httpd'),
    'php-fpm'       => proc_status('php-fpm'),
];

// --- 流量统计(读 /proc/net/dev) ---
$dev = file_get_contents('/proc/net/dev');
$wan_rx = $wan_tx = 0;
foreach (explode("\n", $dev) as $line) {
    if (preg_match('/^\s*(eth\d|wan\d|ppp\d|usb\d):\s+(\d+)\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+(\d+)/', $line, $mm)) {
        $wan_rx += intval($mm[2]);
        $wan_tx += intval($mm[3]);
    }
}
function human_bytes($b) {
    $units = ['B','KB','MB','GB','TB'];
    $i = 0;
    while ($b >= 1024 && $i < count($units) - 1) { $b /= 1024; $i++; }
    return sprintf("%.2f %s", $b, $units[$i]);
}

// --- 新固件检测 ---
$pending_fw = '';
$pend_log = $PREFIX . '/auto_upgrade.log';
if (file_exists($pend_log)) {
    $lines = file($pend_log);
    foreach (array_reverse($lines) as $ln) {
        if (strpos($ln, 'NEW firmware downloaded') !== false) {
            if (preg_match('/to (\S+)/', $ln, $mm)) {
                $pending_fw = $mm[1];
            }
            break;
        }
    }
}

$status = [
    'ts'       => date('Y-m-d H:i:s'),
    'uptime'   => $uptime_str,
    'load'     => [
        '1m'  => $load_parts[0] ?? '?',
        '5m'  => $load_parts[1] ?? '?',
        '15m' => $load_parts[2] ?? '?',
    ],
    'cpu'      => $cpu_pct,
    'memory'   => [
        'total' => $mem_total * 1024,
        'used'  => $mem_used * 1024,
        'free'  => $mem_free * 1024,
        'pct'   => $mem_pct,
    ],
    'disk'     => [
        'total' => $disk_total,
        'used'  => $disk_used,
        'pct'   => $disk_pct,
    ],
    'network'  => [
        'wan_ip' => $wan_ip,
        'lan_ip' => $lan_ip,
        'wan_rx' => $wan_rx,
        'wan_tx' => $wan_tx,
    ],
    'services' => $services,
    'pending_firmware' => $pending_fw,
];

// --- 输出 ---
if ($mode === 'json') {
    @mkdir("$PREFIX/www", 0755, true);
    file_put_contents("$PREFIX/www/status.json", json_encode($status, JSON_PRETTY_PRINT));
    echo "status.json written\n";
} elseif ($mode === 'text') {
    echo "CPU:      {$status['cpu']}%\n";
    echo "Memory:   {$status['memory']['pct']}% (used " . human_bytes($status['memory']['used']) . " / " . human_bytes($status['memory']['total']) . ")\n";
    echo "Disk:     {$status['disk']['pct']}% (used " . human_bytes($status['disk']['used']) . " / " . human_bytes($status['disk']['total']) . ")\n";
    echo "WAN IP:   {$status['network']['wan_ip']}\n";
    echo "Uptime:   {$status['uptime']}\n";
    foreach ($services as $name => $s) {
        $st = $s['status'] === 'up' ? "UP ({$s['mem']})" : "DOWN";
        echo "  $name: $st\n";
    }
} else {
    echo "unknown mode: $mode\n";
    exit(1);
}