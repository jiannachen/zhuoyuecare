mkdir -p app/src/main/java/com/family/babylog

cat << 'EOF' > app/src/main/java/com/family/babylog/DataLayer.kt
package com.family.babylog

import android.app.Application
import android.content.Context
import androidx.room.*
import kotlinx.coroutines.flow.Flow
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

object RecordType {
    const val BOTTLE = "bottle"
    const val BREAST = "breast"
    const val STOOL = "stool"
    const val URINE = "urine"
    const val SPIT = "spit"
    const val WEIGHT = "weight"
}

@Entity(tableName = "baby_records", indices = [Index("timestamp"), Index("type", "timestamp")])
data class BabyRecordEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0L,
    val type: String,
    val timestamp: Long,
    val amount: Int? = null,
    val duration: Int? = null,
    val side: String? = null,
    val condition: String? = null,
    val weight: Double? = null,
    val note: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
)

@Dao
interface BabyRecordDao {
    @Query("SELECT * FROM baby_records WHERE timestamp >= :start AND timestamp < :end ORDER BY timestamp DESC")
    fun observeBetween(start: Long, end: Long): Flow<List<BabyRecordEntity>>

    @Query("SELECT * FROM baby_records WHERE timestamp >= :since ORDER BY timestamp ASC")
    fun observeSince(since: Long): Flow<List<BabyRecordEntity>>

    @Query("SELECT * FROM baby_records WHERE type = 'weight' ORDER BY timestamp ASC")
    fun observeWeights(): Flow<List<BabyRecordEntity>>

    @Query("SELECT * FROM baby_records ORDER BY timestamp ASC")
    suspend fun getAllOnce(): List<BabyRecordEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(record: BabyRecordEntity): Long

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(records: List<BabyRecordEntity>)

    @Update
    suspend fun update(record: BabyRecordEntity)

    @Delete
    suspend fun delete(record: BabyRecordEntity)

    @Query("DELETE FROM baby_records")
    suspend fun deleteAll()

    @Transaction
    suspend fun replaceAll(records: List<BabyRecordEntity>) { deleteAll(); insertAll(records) }
}

@Database(entities = [BabyRecordEntity::class], version = 1, exportSchema = false)
abstract class AppDatabase : RoomDatabase() {
    abstract fun dao(): BabyRecordDao
    companion object {
        @Volatile private var INSTANCE: AppDatabase? = null
        fun get(ctx: Context): AppDatabase = INSTANCE ?: synchronized(this) {
            INSTANCE ?: Room.databaseBuilder(ctx.applicationContext, AppDatabase::class.java, "baby_log.db")
                .build().also { INSTANCE = it }
        }
    }
}

class BabyRecordRepository(private val dao: BabyRecordDao) {
    fun observeDate(date: LocalDate): Flow<List<BabyRecordEntity>> {
        val z = ZoneId.systemDefault()
        return dao.observeBetween(date.atStartOfDay(z).toInstant().toEpochMilli(), date.plusDays(1).atStartOfDay(z).toInstant().toEpochMilli())
    }
    fun observeSinceDays(days: Long): Flow<List<BabyRecordEntity>> =
        dao.observeSince(LocalDate.now().minusDays(days - 1).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli())
    fun observeWeights(): Flow<List<BabyRecordEntity>> = dao.observeWeights()
    suspend fun allOnce(): List<BabyRecordEntity> = dao.getAllOnce()
    suspend fun insert(r: BabyRecordEntity) = System.currentTimeMillis().let { now -> dao.insert(r.copy(createdAt = now, updatedAt = now)) }
    suspend fun update(r: BabyRecordEntity) = dao.update(r.copy(updatedAt = System.currentTimeMillis()))
    suspend fun delete(r: BabyRecordEntity) = dao.delete(r)
    suspend fun replaceAll(list: List<BabyRecordEntity>) = dao.replaceAll(list)
    suspend fun deleteAll() = dao.deleteAll()
}

object BackupSerializer {
    private val fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(ZoneId.systemDefault())
    fun toJson(records: List<BabyRecordEntity>): String {
        val arr = JSONArray()
        records.forEach { r ->
            arr.put(JSONObject().apply {
                put("id", r.id); put("type", r.type); put("timestamp", r.timestamp)
                put("amount", r.amount ?: JSONObject.NULL); put("duration", r.duration ?: JSONObject.NULL)
                put("side", r.side ?: JSONObject.NULL); put("condition", r.condition ?: JSONObject.NULL)
                put("weight", r.weight ?: JSONObject.NULL); put("note", r.note ?: JSONObject.NULL)
                put("createdAt", r.createdAt); put("updatedAt", r.updatedAt)
            })
        }
        return JSONObject().apply { put("version", 1); put("exportedAt", System.currentTimeMillis()); put("records", arr) }.toString(2)
    }
    fun fromJson(text: String): List<BabyRecordEntity> {
        val arr = JSONObject(text).getJSONArray("records")
        val now = System.currentTimeMillis()
        return List(arr.length()) { i ->
            val o = arr.getJSONObject(i)
            BabyRecordEntity(
                id = 0L, type = o.getString("type"), timestamp = o.getLong("timestamp"),
                amount = if (o.isNull("amount")) null else o.getInt("amount"),
                duration = if (o.isNull("duration")) null else o.getInt("duration"),
                side = if (o.isNull("side")) null else o.getString("side"),
                condition = if (o.isNull("condition")) null else o.getString("condition"),
                weight = if (o.isNull("weight")) null else o.getDouble("weight"),
                note = if (o.isNull("note")) null else o.getString("note"),
                createdAt = o.optLong("createdAt", now), updatedAt = o.optLong("updatedAt", now)
            )
        }
    }
    fun toCsv(records: List<BabyRecordEntity>): String {
        val sb = StringBuilder("\uFEFF时间,类型,奶量(ml),时长(分钟),喂养侧,性状或程度,体重(kg),备注\n")
        records.forEach { r ->
            val note = "\"${(r.note ?: "").replace("\"", "\"\"")}\""
            sb.appendLine(listOf(fmt.format(Instant.ofEpochMilli(r.timestamp)), r.type, r.amount ?: "", r.duration ?: "", r.side ?: "", r.condition ?: "", r.weight ?: "", note).joinToString(","))
        }
        return sb.toString()
    }
}

class BabyLogApp : Application() {
    val repository: BabyRecordRepository by lazy { BabyRecordRepository(AppDatabase.get(this).dao()) }
}
EOF

cat << 'EOF' > app/src/main/java/com/family/babylog/MainViewModel.kt
package com.family.babylog

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

data class DaySummary(
    val totalMilkMl: Int = 0, val breastCount: Int = 0, val bottleCount: Int = 0,
    val stoolCount: Int = 0, val urineCount: Int = 0, val spitCount: Int = 0,
    val lastFeedingTimestamp: Long? = null
)

data class DailyTrendPoint(val label: String, val milkMl: Int, val feedingCount: Int, val stoolCount: Int, val urineCount: Int)

data class StatsState(
    val last7Days: List<DailyTrendPoint> = emptyList(),
    val last30Days: List<DailyTrendPoint> = emptyList(),
    val avgMilk7Days: Int = 0, val avgFeeding7Days: Double = 0.0,
    val avgStool7Days: Double = 0.0, val avgUrine7Days: Double = 0.0,
    val weightRecords: List<BabyRecordEntity> = emptyList(),
    val alerts: List<String> = emptyList()
)

@OptIn(ExperimentalCoroutinesApi::class)
class MainViewModel(private val repo: BabyRecordRepository) : ViewModel() {
    private val todayDate = MutableStateFlow(LocalDate.now())
    private val _historyDate = MutableStateFlow(LocalDate.now())
    val selectedHistoryDate: StateFlow<LocalDate> = _historyDate.asStateFlow()

    val todayRecords = todayDate.flatMapLatest { repo.observeDate(it) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    val todaySummary = todayRecords.map { summarize(it) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), DaySummary())

    val historyRecords = _historyDate.flatMapLatest { repo.observeDate(it) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    val historySummary = historyRecords.map { summarize(it) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), DaySummary())

    val statsState = combine(repo.observeSinceDays(30), repo.observeWeights()) { r30, weights ->
        buildStats(r30, weights)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), StatsState())

    fun refreshToday() { val now = LocalDate.now(); if (todayDate.value != now) todayDate.value = now }
    fun selectHistoryDate(d: LocalDate) { _historyDate.value = d }
    fun saveRecord(r: BabyRecordEntity) { viewModelScope.launch { if (r.id == 0L) repo.insert(r) else repo.update(r) } }
    fun deleteRecord(r: BabyRecordEntity) { viewModelScope.launch { repo.delete(r) } }
    suspend fun exportJson() = BackupSerializer.toJson(repo.allOnce())
    suspend fun exportCsv() = BackupSerializer.toCsv(repo.allOnce())
    suspend fun importRecords(list: List<BabyRecordEntity>) = repo.replaceAll(list)
    suspend fun deleteAllData() = repo.deleteAll()

    private fun summarize(list: List<BabyRecordEntity>): DaySummary {
        var milk = 0; var breast = 0; var bottle = 0; var stool = 0; var urine = 0; var spit = 0
        var lastFeed: Long? = null
        list.forEach { r ->
            when (r.type) {
                RecordType.BOTTLE -> { bottle++; milk += r.amount ?: 0; lastFeed = maxOf(lastFeed ?: 0L, r.timestamp) }
                RecordType.BREAST -> { breast++; lastFeed = maxOf(lastFeed ?: 0L, r.timestamp) }
                RecordType.STOOL -> stool++
                RecordType.URINE -> urine++
                RecordType.SPIT -> spit++
            }
        }
        return DaySummary(milk, breast, bottle, stool, urine, spit, lastFeed)
    }

    private fun buildStats(records30: List<BabyRecordEntity>, weights: List<BabyRecordEntity>): StatsState {
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val fmt = DateTimeFormatter.ofPattern("MM/dd")
        val byDate = records30.groupBy { Instant.ofEpochMilli(it.timestamp).atZone(zone).toLocalDate() }
        val last30 = (29 downTo 0).map { offset ->
            val d = today.minusDays(offset.toLong())
            val dayList = byDate[d].orEmpty()
            DailyTrendPoint(
                label = d.format(fmt),
                milkMl = dayList.filter { it.type == RecordType.BOTTLE }.sumOf { it.amount ?: 0 },
                feedingCount = dayList.count { it.type == RecordType.BOTTLE || it.type == RecordType.BREAST },
                stoolCount = dayList.count { it.type == RecordType.STOOL },
                urineCount = dayList.count { it.type == RecordType.URINE }
            )
        }
        val last7 = last30.takeLast(7)
        val alerts = mutableListOf<String>()
        val r3 = last30.takeLast(3).map { it.milkMl }.average()
        val p7 = last30.dropLast(3).takeLast(7).map { it.milkMl }.average()
        if (p7 > 100 && r3 < p7 * 0.85) alerts.add("最近 3 天日均奶瓶奶量（${r3.toInt()} ml）比前 7 天（${p7.toInt()} ml）有所下降，仅作统计参考。")
        if ((last30.lastOrNull()?.stoolCount ?: 0) == 0) alerts.add("今天暂未记录大便。")

        return StatsState(
            last7Days = last7, last30Days = last30,
            avgMilk7Days = last7.sumOf { it.milkMl } / 7,
            avgFeeding7Days = last7.sumOf { it.feedingCount } / 7.0,
            avgStool7Days = last7.sumOf { it.stoolCount } / 7.0,
            avgUrine7Days = last7.sumOf { it.urineCount } / 7.0,
            weightRecords = weights, alerts = alerts
        )
    }

    class Factory(private val repo: BabyRecordRepository) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T = MainViewModel(repo) as T
    }
}
EOF
