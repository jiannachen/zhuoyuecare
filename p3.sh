cat << 'EOF' > app/src/main/java/com/family/babylog/UiComponents.kt
package com.family.babylog

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import java.time.*
import java.time.format.DateTimeFormatter

private val timeFmt = DateTimeFormatter.ofPattern("HH:mm").withZone(ZoneId.systemDefault())
fun formatRecordTime(ts: Long): String = timeFmt.format(Instant.ofEpochMilli(ts))

fun formatRecordEmoji(type: String): String = when (type) {
    RecordType.BOTTLE -> "🍼"; RecordType.BREAST -> "🤱"; RecordType.STOOL -> "💩"
    RecordType.URINE -> "💧"; RecordType.SPIT -> "🤮"; RecordType.WEIGHT -> "⚖️"; else -> "📝"
}

fun formatRecordTitle(r: BabyRecordEntity): String = when (r.type) {
    RecordType.BOTTLE -> (if (r.condition == "breast_milk") "母乳瓶喂" else "配方奶") + " ${r.amount ?: 0} ml"
    RecordType.BREAST -> "亲喂母乳 ${r.duration ?: 0} 分钟 (" + when (r.side) { "left" -> "左侧"; "right" -> "右侧"; else -> "双侧" } + ")"
    RecordType.STOOL -> "大便 (" + when (r.condition) { "loose" -> "稀"; "dry" -> "偏干"; "other" -> "其他"; else -> "正常" } + ")"
    RecordType.URINE -> "小便"
    RecordType.SPIT -> "吐奶 (" + when (r.condition) { "large" -> "较多"; "medium" -> "中等"; else -> "少量" } + ")"
    RecordType.WEIGHT -> "体重 ${r.weight ?: 0.0} kg"
    else -> r.type
}

fun formatDurationSince(lastMs: Long?, nowMs: Long): String {
    if (lastMs == null) return "暂无喂养记录"
    val mins = ((nowMs - lastMs) / 60_000L).coerceAtLeast(0L)
    val h = mins / 60L; val m = mins % 60L
    return if (h > 0) "距离上次喂养：$h 小时 $m 分钟" else "距离上次喂养：$m 分钟"
}

data class ChartPoint(val label: String, val value: Float)

@Composable
fun SimpleBarChart(items: List<ChartPoint>, barColor: Color) {
    if (items.isEmpty()) { Text("暂无数据"); return }
    val maxVal = (items.maxOfOrNull { it.value } ?: 0f).coerceAtLeast(1f)
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().height(140.dp), Arrangement.SpaceEvenly, Alignment.Bottom) {
            items.forEach { item ->
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Bottom) {
                    Text(if (item.value > 0f) item.value.toInt().toString() else "", style = MaterialTheme.typography.labelSmall, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(4.dp))
                    Canvas(Modifier.width(20.dp).height(100.dp)) {
                        val h = (item.value / maxVal) * size.height
                        if (h > 0f) drawRoundRect(barColor, Offset(0f, size.height - h), Size(size.width, h), CornerRadius(8f, 8f))
                    }
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceEvenly) {
            items.forEach { Text(it.label, Modifier.weight(1f), textAlign = TextAlign.Center, style = MaterialTheme.typography.labelSmall) }
        }
    }
}

@Composable
fun SimpleLineChart(items: List<ChartPoint>, lineColor: Color, unitSuffix: String = "") {
    if (items.isEmpty()) { Text("暂无数据"); return }
    val minV = items.minOf { it.value }; val maxV = items.maxOf { it.value }
    val span = (maxV - minV).takeIf { it > 0.001f } ?: 1f
    val fmtNum: (Float) -> String = { if (it % 1f == 0f) it.toInt().toString() else String.format("%.1f", it) }
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) {
            Text("最低 ${fmtNum(minV)}$unitSuffix", style = MaterialTheme.typography.labelSmall)
            Text("最高 ${fmtNum(maxV)}$unitSuffix", style = MaterialTheme.typography.labelSmall)
        }
        Spacer(Modifier.height(6.dp))
        Canvas(Modifier.fillMaxWidth().height(125.dp).padding(8.dp)) {
            if (items.size == 1) { drawCircle(lineColor, 10f, Offset(size.width / 2f, size.height / 2f)); return@Canvas }
            val stepX = size.width / (items.size - 1).coerceAtLeast(1)
            val path = Path()
            val pts = items.mapIndexed { i, p -> Offset(i * stepX, size.height - ((p.value - minV) / span) * size.height) }
            pts.forEachIndexed { i, pt -> if (i == 0) path.moveTo(pt.x, pt.y) else path.lineTo(pt.x, pt.y) }
            drawPath(path, lineColor, style = Stroke(6f, cap = StrokeCap.Round))
            if (pts.size <= 16) pts.forEach { drawCircle(lineColor, 7f, it) }
        }
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) {
            Text(items.first().label, style = MaterialTheme.typography.labelSmall)
            if (items.size >= 3) Text(items[items.size / 2].label, style = MaterialTheme.typography.labelSmall)
            Text(items.last().label, style = MaterialTheme.typography.labelSmall)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecordEditorSheet(
    initialType: String, editingRecord: BabyRecordEntity?, defaultDate: LocalDate,
    onDismiss: () -> Unit, onSave: (BabyRecordEntity) -> Unit, onDelete: (BabyRecordEntity) -> Unit
) {
    val zone = ZoneId.systemDefault()
    val initDT = remember(editingRecord, defaultDate) {
        editingRecord?.let { Instant.ofEpochMilli(it.timestamp).atZone(zone).toLocalDateTime() }
            ?: LocalDateTime.of(defaultDate, LocalTime.now())
    }
    var date by remember { mutableStateOf(initDT.toLocalDate()) }
    var time by remember { mutableStateOf(initDT.toLocalTime()) }
    var bottleType by remember { mutableStateOf(editingRecord?.condition ?: "formula") }
    var amountText by remember { mutableStateOf((editingRecord?.amount ?: 90).toString()) }
    var durationText by remember { mutableStateOf((editingRecord?.duration ?: 15).toString()) }
    var side by remember { mutableStateOf(editingRecord?.side ?: "both") }
    var stoolCond by remember { mutableStateOf(editingRecord?.condition ?: "normal") }
    var spitCond by remember { mutableStateOf(editingRecord?.condition ?: "small") }
    var weightText by remember { mutableStateOf(editingRecord?.weight?.toString() ?: "") }
    var noteText by remember { mutableStateOf(editingRecord?.note ?: "") }
    var showDate by remember { mutableStateOf(false) }
    var showTime by remember { mutableStateOf(false) }
    var showDelConfirm by remember { mutableStateOf(false) }
    val activeType = editingRecord?.type ?: initialType
    val typeName = when (activeType) {
        RecordType.BOTTLE -> "喝奶"; RecordType.BREAST -> "亲喂母乳"; RecordType.STOOL -> "大便"
        RecordType.URINE -> "小便"; RecordType.SPIT -> "吐奶"; RecordType.WEIGHT -> "体重"; else -> "记录"
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text((if (editingRecord == null) "记一笔 · " else "编辑 · ") + typeName, style = MaterialTheme.typography.titleLarge)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(onClick = { showDate = true }, modifier = Modifier.weight(1f)) { Text(date.toString()) }
                OutlinedButton(onClick = { showTime = true }, modifier = Modifier.weight(1f)) { Text(time.format(DateTimeFormatter.ofPattern("HH:mm"))) }
            }

            when (activeType) {
                RecordType.BOTTLE -> {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilterChip(selected = bottleType == "formula", onClick = { bottleType = "formula" }, label = { Text("配方奶") })
                        FilterChip(selected = bottleType == "breast_milk", onClick = { bottleType = "breast_milk" }, label = { Text("母乳瓶喂") })
                    }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf(60, 90, 120, 150).forEach { ml ->
                            FilterChip(selected = amountText == ml.toString(), onClick = { amountText = ml.toString() }, label = { Text("${ml}ml") }, modifier = Modifier.weight(1f))
                        }
                    }
                    OutlinedTextField(value = amountText, onValueChange = { amountText = it.filter(Char::isDigit) }, label = { Text("奶量 (ml)") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true, modifier = Modifier.fillMaxWidth())
                }
                RecordType.BREAST -> {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf("left" to "左侧", "right" to "右侧", "both" to "双侧").forEach { (v, l) ->
                            FilterChip(selected = side == v, onClick = { side = v }, label = { Text(l) }, modifier = Modifier.weight(1f))
                        }
                    }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf(10, 15, 20, 30).forEach { m ->
                            FilterChip(selected = durationText == m.toString(), onClick = { durationText = m.toString() }, label = { Text("${m}分") }, modifier = Modifier.weight(1f))
                        }
                    }
                    OutlinedTextField(value = durationText, onValueChange = { durationText = it.filter(Char::isDigit) }, label = { Text("时长 (分钟)") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true, modifier = Modifier.fillMaxWidth())
                }
                RecordType.STOOL -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf("normal" to "正常", "loose" to "稀", "dry" to "偏干", "other" to "其他").forEach { (v, l) ->
                        FilterChip(selected = stoolCond == v, onClick = { stoolCond = v }, label = { Text(l) }, modifier = Modifier.weight(1f))
                    }
                }
                RecordType.URINE -> Text("确认时间后直接保存，无需输入毫升数。", style = MaterialTheme.typography.bodyMedium)
                RecordType.SPIT -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("small" to "少量", "medium" to "中等", "large" to "较多").forEach { (v, l) ->
                        FilterChip(selected = spitCond == v, onClick = { spitCond = v }, label = { Text(l) }, modifier = Modifier.weight(1f))
                    }
                }
                RecordType.WEIGHT -> OutlinedTextField(value = weightText, onValueChange = { s -> weightText = s.filter { it.isDigit() || it == '.' } },
                    label = { Text("体重 (kg)，如 5.2") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true, modifier = Modifier.fillMaxWidth())
            }

            if (activeType != RecordType.URINE) {
                OutlinedTextField(value = noteText, onValueChange = { noteText = it }, label = { Text("备注（可选）") }, maxLines = 3, modifier = Modifier.fillMaxWidth())
            }

            val canSave = when (activeType) {
                RecordType.BOTTLE -> (amountText.toIntOrNull() ?: 0) > 0
                RecordType.BREAST -> (durationText.toIntOrNull() ?: 0) > 0
                RecordType.WEIGHT -> (weightText.toDoubleOrNull() ?: 0.0) > 0.0
                else -> true
            }
            Button(
                onClick = {
                    val ms = LocalDateTime.of(date, time).atZone(zone).toInstant().toEpochMilli()
                    onSave(BabyRecordEntity(
                        id = editingRecord?.id ?: 0L, type = activeType, timestamp = ms,
                        amount = if (activeType == RecordType.BOTTLE) amountText.toIntOrNull() else null,
                        duration = if (activeType == RecordType.BREAST) durationText.toIntOrNull() else null,
                        side = if (activeType == RecordType.BREAST) side else null,
                        condition = when (activeType) { RecordType.BOTTLE -> bottleType; RecordType.STOOL -> stoolCond; RecordType.SPIT -> spitCond; else -> null },
                        weight = if (activeType == RecordType.WEIGHT) weightText.toDoubleOrNull() else null,
                        note = if (activeType == RecordType.URINE) null else noteText.trim().ifEmpty { null },
                        createdAt = editingRecord?.createdAt ?: System.currentTimeMillis()
                    ))
                },
                enabled = canSave, modifier = Modifier.fillMaxWidth().height(52.dp)
            ) { Text("确认保存", style = MaterialTheme.typography.titleMedium) }

            if (editingRecord != null) {
                TextButton(onClick = { showDelConfirm = true }, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error), modifier = Modifier.align(Alignment.CenterHorizontally)) {
                    Text("删除这条记录")
                }
            }
        }
    }

    if (showDate) {
        val state = rememberDatePickerState(date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(onDismissRequest = { showDate = false }, confirmButton = {
            TextButton(onClick = { state.selectedDateMillis?.let { date = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate() }; showDate = false }) { Text("确定") }
        }, dismissButton = { TextButton(onClick = { showDate = false }) { Text("取消") } }) { DatePicker(state) }
    }
    if (showTime) {
        val st = rememberTimePickerState(time.hour, time.minute, true)
        AlertDialog(onDismissRequest = { showTime = false }, title = { Text("选择时间") }, text = { TimePicker(st) },
            confirmButton = { TextButton(onClick = { time = LocalTime.of(st.hour, st.minute); showTime = false }) { Text("确定") } },
            dismissButton = { TextButton(onClick = { showTime = false }) { Text("取消") } })
    }
    if (showDelConfirm && editingRecord != null) {
        AlertDialog(onDismissRequest = { showDelConfirm = false }, title = { Text("删除记录") }, text = { Text("确定删除这条${typeName}记录吗？") },
            confirmButton = { TextButton(onClick = { showDelConfirm = false; onDelete(editingRecord) }) { Text("删除") } },
            dismissButton = { TextButton(onClick = { showDelConfirm = false }) { Text("取消") } })
    }
}
EOF
