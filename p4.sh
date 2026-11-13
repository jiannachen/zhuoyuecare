cat << 'EOF' > app/src/main/java/com/family/babylog/MainActivity.kt
package com.family.babylog

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

private enum class MainTab(val title: String) { TODAY("濯玥 · 今天"), HISTORY("记录"), STATS("统计") }

private val ZhuoYueColors = lightColorScheme(
    primary = Color(0xFFD1667B), onPrimary = Color.White,
    primaryContainer = Color(0xFFFCE8EC), onPrimaryContainer = Color(0xFF5C1D2B),
    secondary = Color(0xFF9E6B75), secondaryContainer = Color(0xFFF5ECEE),
    tertiary = Color(0xFF8C6D46), background = Color(0xFFFFFBFA), surface = Color(0xFFFFFFFF)
)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as BabyLogApp
        setContent {
            MaterialTheme(colorScheme = ZhuoYueColors) {
                BabyLogRoot(viewModel(factory = MainViewModel.Factory(app.repository)))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BabyLogRoot(vm: MainViewModel) {
    var tab by remember { mutableStateOf(MainTab.TODAY) }
    var showSettings by remember { mutableStateOf(false) }
    var editorType by remember { mutableStateOf<String?>(null) }
    var editing by remember { mutableStateOf<BabyRecordEntity?>(null) }
    var defaultDate by remember { mutableStateOf(LocalDate.now()) }

    val todaySum by vm.todaySummary.collectAsState()
    val todayList by vm.todayRecords.collectAsState()
    val histDate by vm.selectedHistoryDate.collectAsState()
    val histSum by vm.historySummary.collectAsState()
    val histList by vm.historyRecords.collectAsState()
    val stats by vm.statsState.collectAsState()
    val snack = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    LaunchedEffect(tab) { vm.refreshToday() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (showSettings) "设置与备份" else tab.title) },
                actions = {
                    IconButton(onClick = { showSettings = !showSettings }) {
                        Icon(if (showSettings) Icons.Default.Close else Icons.Default.Settings, null)
                    }
                }
            )
        },
        bottomBar = {
            if (!showSettings) NavigationBar {
                NavigationBarItem(tab == MainTab.TODAY, { tab = MainTab.TODAY }, { Icon(Icons.Default.Home, null) }, label = { Text("今天") })
                NavigationBarItem(tab == MainTab.HISTORY, { tab = MainTab.HISTORY }, { Icon(Icons.Default.DateRange, null) }, label = { Text("记录") })
                NavigationBarItem(tab == MainTab.STATS, { tab = MainTab.STATS }, { Icon(Icons.Default.Info, null) }, label = { Text("统计") })
            }
        },
        snackbarHost = { SnackbarHost(snack) }
    ) { pad ->
        if (showSettings) {
            SettingsScreen(vm, { msg -> scope.launch { snack.showSnackbar(msg) } }, Modifier.padding(pad))
        } else when (tab) {
            MainTab.TODAY -> TodayScreen(todaySum, todayList, { t -> editing = null; defaultDate = LocalDate.now(); editorType = t }, { r -> editing = r; editorType = r.type }, Modifier.padding(pad))
            MainTab.HISTORY -> HistoryScreen(histDate, histSum, histList, vm::selectHistoryDate, { r -> editing = r; editorType = r.type }, { t -> editing = null; defaultDate = histDate; editorType = t }, Modifier.padding(pad))
            MainTab.STATS -> StatsScreen(stats, Modifier.padding(pad))
        }
    }

    editorType?.let { t ->
        RecordEditorSheet(t, editing, defaultDate, { editorType = null; editing = null },
            { r -> vm.saveRecord(r); editorType = null; editing = null; scope.launch { snack.showSnackbar("已保存") } },
            { r -> vm.deleteRecord(r); editorType = null; editing = null; scope.launch { snack.showSnackbar("已删除") } })
    }
}

@Composable
private fun TodayScreen(summary: DaySummary, records: List<BabyRecordEntity>, onAdd: (String) -> Unit, onClick: (BabyRecordEntity) -> Unit, modifier: Modifier) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { now = System.currentTimeMillis(); delay(30_000L) } }

    LazyColumn(modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            ElevatedCard(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(formatDurationSince(summary.lastFeedingTimestamp, now), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
                    HorizontalDivider()
                    Row(Modifier.fillMaxWidth()) {
                        MetricBox("今日奶量", "${summary.totalMilkMl} ml", Modifier.weight(1f))
                        MetricBox("亲喂母乳", "${summary.breastCount} 次", Modifier.weight(1f))
                        MetricBox("大便", "${summary.stoolCount} 次", Modifier.weight(1f))
                    }
                    Row(Modifier.fillMaxWidth()) {
                        MetricBox("小便", "${summary.urineCount} 次", Modifier.weight(1f))
                        MetricBox("吐奶", "${summary.spitCount} 次", Modifier.weight(1f))
                        MetricBox("奶瓶", "${summary.bottleCount} 次", Modifier.weight(1f))
                    }
                }
            }
        }
        item {
            Text("快速记录", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    QuickBtn("🍼 喝奶", Modifier.weight(1f)) { onAdd(RecordType.BOTTLE) }
                    QuickBtn("🤱 亲喂母乳", Modifier.weight(1f)) { onAdd(RecordType.BREAST) }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    QuickBtn("💩 大便", Modifier.weight(1f)) { onAdd(RecordType.STOOL) }
                    QuickBtn("💧 小便", Modifier.weight(1f)) { onAdd(RecordType.URINE) }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    QuickBtn("🤮 吐奶", Modifier.weight(1f)) { onAdd(RecordType.SPIT) }
                    QuickBtn("⚖️ 体重", Modifier.weight(1f)) { onAdd(RecordType.WEIGHT) }
                }
            }
        }
        item { Text("今日时间线 (${records.size})", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 4.dp)) }
        if (records.isEmpty()) {
            item { Text("今天还没有记录，点击上方按钮即可快速记一笔。", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        } else {
            items(records, key = { it.id }) { TimelineRow(it) { onClick(it) } }
        }
    }
}

@Composable
private fun MetricBox(label: String, value: String, modifier: Modifier) {
    Column(modifier) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun QuickBtn(text: String, modifier: Modifier, onClick: () -> Unit) {
    FilledTonalButton(onClick, modifier.height(60.dp), shape = RoundedCornerShape(14.dp)) {
        Text(text, style = MaterialTheme.typography.titleMedium)
    }
}

@Composable
private fun TimelineRow(r: BabyRecordEntity, onClick: () -> Unit) {
    Card(Modifier.fillMaxWidth().clickable(onClick = onClick), shape = RoundedCornerShape(12.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(formatRecordTime(r.timestamp), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary, modifier = Modifier.width(64.dp))
            Text(formatRecordEmoji(r.type), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(end = 8.dp))
            Column(Modifier.weight(1f)) {
                Text(formatRecordTitle(r), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                r.note?.takeIf { it.isNotBlank() }?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HistoryScreen(date: LocalDate, summary: DaySummary, records: List<BabyRecordEntity>, onDate: (LocalDate) -> Unit, onClick: (BabyRecordEntity) -> Unit, onAdd: (String) -> Unit, modifier: Modifier) {
    var showPicker by remember { mutableStateOf(false) }
    var showMenu by remember { mutableStateOf(false) }
    val fmt = remember { DateTimeFormatter.ofPattern("yyyy-MM-dd (E)") }
    LazyColumn(modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                        TextButton({ onDate(date.minusDays(1)) }) { Text("< 前一天") }
                        OutlinedButton({ showPicker = true }) { Text(date.format(fmt)) }
                        TextButton({ onDate(date.plusDays(1)) }) { Text("后一天 >") }
                    }
                    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                        Text("奶量 ${summary.totalMilkMl}ml · 亲喂 ${summary.breastCount} · 大便 ${summary.stoolCount} · 小便 ${summary.urineCount}", style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                        Box {
                            TextButton({ showMenu = true }) { Text("+ 补录") }
                            DropdownMenu(showMenu, { showMenu = false }) {
                                listOf(RecordType.BOTTLE to "🍼 喝奶", RecordType.BREAST to "🤱 亲喂母乳", RecordType.STOOL to "💩 大便", RecordType.URINE to "💧 小便", RecordType.SPIT to "🤮 吐奶", RecordType.WEIGHT to "⚖️ 体重").forEach { (t, l) ->
                                    DropdownMenuItem({ Text(l) }, { showMenu = false; onAdd(t) })
                                }
                            }
                        }
                    }
                }
            }
        }
        if (records.isEmpty()) item { Text("该日期暂无记录，可点击“+ 补录”添加。", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        else items(records, key = { it.id }) { TimelineRow(it) { onClick(it) } }
    }
    if (showPicker) {
        val st = rememberDatePickerState(date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(onDismissRequest = { showPicker = false }, confirmButton = {
            TextButton({ st.selectedDateMillis?.let { onDate(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()) }; showPicker = false }) { Text("确定") }
        }, dismissButton = { TextButton({ showPicker = false }) { Text("取消") } }) { DatePicker(st) }
    }
}

@Composable
private fun StatsScreen(stats: StatsState, modifier: Modifier) {
    val wFmt = DateTimeFormatter.ofPattern("MM/dd").withZone(ZoneId.systemDefault())
    LazyColumn(modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        if (stats.alerts.isNotEmpty()) {
            item {
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer), modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("数据观察提示（非医疗诊断）", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                        stats.alerts.forEach { Text("• $it", style = MaterialTheme.typography.bodyMedium) }
                    }
                }
            }
        }
        item {
            ElevatedCard(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("最近 7 天日均统计", style = MaterialTheme.typography.titleMedium)
                    Row(Modifier.fillMaxWidth()) {
                        MetricBox("日均奶量", "${stats.avgMilk7Days} ml", Modifier.weight(1f))
                        MetricBox("日均喂养", String.format("%.1f 次", stats.avgFeeding7Days), Modifier.weight(1f))
                    }
                    Row(Modifier.fillMaxWidth()) {
                        MetricBox("日均大便", String.format("%.1f 次", stats.avgStool7Days), Modifier.weight(1f))
                        MetricBox("日均小便", String.format("%.1f 次", stats.avgUrine7Days), Modifier.weight(1f))
                    }
                }
            }
        }
        item { ElevatedCard(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp)) { Text("最近 7 天每日奶量 (ml)", style = MaterialTheme.typography.titleMedium); Spacer(Modifier.height(8.dp)); SimpleBarChart(stats.last7Days.map { ChartPoint(it.label, it.milkMl.toFloat()) }, MaterialTheme.colorScheme.primary) } } }
        item { ElevatedCard(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp)) { Text("最近 7 天大便次数", style = MaterialTheme.typography.titleMedium); Spacer(Modifier.height(8.dp)); SimpleBarChart(stats.last7Days.map { ChartPoint(it.label, it.stoolCount.toFloat()) }, MaterialTheme.colorScheme.tertiary) } } }
        item { ElevatedCard(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp)) { Text("最近 7 天小便次数", style = MaterialTheme.typography.titleMedium); Spacer(Modifier.height(8.dp)); SimpleBarChart(stats.last7Days.map { ChartPoint(it.label, it.urineCount.toFloat()) }, MaterialTheme.colorScheme.secondary) } } }
        item { ElevatedCard(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp)) { Text("最近 30 天奶量趋势 (ml)", style = MaterialTheme.typography.titleMedium); Spacer(Modifier.height(8.dp)); SimpleLineChart(stats.last30Days.map { ChartPoint(it.label, it.milkMl.toFloat()) }, MaterialTheme.colorScheme.primary, " ml") } } }
        item { ElevatedCard(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp)) { Text("最近 30 天大小便总次数趋势", style = MaterialTheme.typography.titleMedium); Spacer(Modifier.height(8.dp)); SimpleLineChart(stats.last30Days.map { ChartPoint(it.label, (it.stoolCount + it.urineCount).toFloat()) }, MaterialTheme.colorScheme.secondary, " 次") } } }
        item {
            ElevatedCard(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    val lw = stats.weightRecords.lastOrNull()?.weight
                    Text(if (lw != null) "体重长期趋势（最新 ${lw} kg）" else "体重长期趋势", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(8.dp))
                    SimpleLineChart(stats.weightRecords.mapNotNull { r -> r.weight?.let { ChartPoint(wFmt.format(Instant.ofEpochMilli(r.timestamp)), it.toFloat()) } }, MaterialTheme.colorScheme.tertiary, " kg")
                }
            }
        }
    }
}

@Composable
private fun SettingsScreen(vm: MainViewModel, onMsg: (String) -> Unit, modifier: Modifier) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var pendingImport by remember { mutableStateOf<List<BabyRecordEntity>?>(null) }
    var confirmDel by remember { mutableStateOf(false) }

    val expJson = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            runCatching {
                val s = vm.exportJson()
                withContext(Dispatchers.IO) { ctx.contentResolver.openOutputStream(uri)?.use { it.write(s.toByteArray()) } }
            }.onSuccess { onMsg("JSON 备份已保存") }.onFailure { onMsg("导出失败: ${it.message}") }
        }
    }
    val expCsv = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/csv")) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            runCatching {
                val s = vm.exportCsv()
                withContext(Dispatchers.IO) { ctx.contentResolver.openOutputStream(uri)?.use { it.write(s.toByteArray()) } }
            }.onSuccess { onMsg("CSV 已导出") }.onFailure { onMsg("导出失败: ${it.message}") }
        }
    }
    val impJson = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            runCatching {
                val txt = withContext(Dispatchers.IO) { ctx.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() } ?: "" }
                BackupSerializer.fromJson(txt)
            }.onSuccess { pendingImport = it }.onFailure { onMsg("解析失败: ${it.message}") }
        }
    }

    Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("濯玥的记录仅保存在本机，建议定期导出 JSON 备份。", color = MaterialTheme.colorScheme.onSurfaceVariant)
        Button({ expJson.launch("zhuoyue-record-backup.json") }, Modifier.fillMaxWidth().height(50.dp)) { Text("导出全部数据 (JSON 备份)") }
        OutlinedButton({ impJson.launch(arrayOf("application/json", "*/*")) }, Modifier.fillMaxWidth().height(50.dp)) { Text("导入备份恢复数据 (JSON)") }
        OutlinedButton({ expCsv.launch("zhuoyue-record-export.csv") }, Modifier.fillMaxWidth().height(50.dp)) { Text("导出表格文件 (CSV)") }
        Spacer(Modifier.height(12.dp))
        Button({ confirmDel = true }, colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error), modifier = Modifier.fillMaxWidth().height(50.dp)) { Text("删除全部本地数据") }
    }

    pendingImport?.let { list ->
        AlertDialog(onDismissRequest = { pendingImport = null }, title = { Text("确认导入备份") },
            text = { Text("共读取到 ${list.size} 条记录，导入将覆盖当前数据，确认继续吗？") },
            confirmButton = { TextButton({ pendingImport = null; scope.launch { vm.importRecords(list); onMsg("已恢复 ${list.size} 条记录") } }) { Text("确认覆盖") } },
            dismissButton = { TextButton({ pendingImport = null }) { Text("取消") } })
    }
    if (confirmDel) {
        AlertDialog(onDismissRequest = { confirmDel = false }, title = { Text("清空全部数据") }, text = { Text("此操作会永久删除全部本地记录且无法恢复，确定删除吗？") },
            confirmButton = { TextButton({ confirmDel = false; scope.launch { vm.deleteAllData(); onMsg("已清空全部数据") } }) { Text("确认删除") } },
            dismissButton = { TextButton({ confirmDel = false }) { Text("取消") } })
    }
}
EOF
