package dev.shuye.shuye_reader

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

open class ShuyeWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val prefs = context.getSharedPreferences("shuye_widgets",Context.MODE_PRIVATE)
        val key = when(javaClass.simpleName) { "BookshelfWidget" -> "shelf"; "CurrentBookWidget" -> "current"; "HeatmapWidget" -> "heatmap"; "WeeklyWidget" -> "weekly"; "QuoteWidget" -> "quote"; "BookListWidget" -> "lists"; else -> "stats" }
        val title = mapOf("shelf" to "我的书架","current" to "继续阅读","heatmap" to "阅读热力图","weekly" to "本周阅读","quote" to "一日一摘","lists" to "我的书单","stats" to "阅读足迹")[key]
        for(id in ids) {
            val view=RemoteViews(context.packageName,R.layout.shuye_widget)
            view.setTextViewText(R.id.widget_title,"书叶 · $title")
            view.setTextViewText(R.id.widget_body,prefs.getString(key,"打开书叶，开始你的第一段阅读"))
            val intent=Intent(context,MainActivity::class.java).apply { flags=Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP; data=android.net.Uri.parse(prefs.getString("link","shuye://library")) }
            view.setOnClickPendingIntent(R.id.widget_root,PendingIntent.getActivity(context,id,intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            manager.updateAppWidget(id,view)
        }
    }
    companion object {
        fun refresh(context:Context) {
            val manager=AppWidgetManager.getInstance(context)
            listOf(StatsWidget::class.java,BookshelfWidget::class.java,CurrentBookWidget::class.java,HeatmapWidget::class.java,WeeklyWidget::class.java,QuoteWidget::class.java,BookListWidget::class.java).forEach { cls ->
                val ids=manager.getAppWidgetIds(ComponentName(context,cls))
                if(ids.isNotEmpty()) {context.sendBroadcast(Intent(context,cls).apply {action=AppWidgetManager.ACTION_APPWIDGET_UPDATE;putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS,ids)})}
            }
        }
    }
}
class StatsWidget : ShuyeWidget()
class BookshelfWidget : ShuyeWidget()
class CurrentBookWidget : ShuyeWidget()
class HeatmapWidget : ShuyeWidget()
class WeeklyWidget : ShuyeWidget()
class QuoteWidget : ShuyeWidget()
class BookListWidget : ShuyeWidget()
