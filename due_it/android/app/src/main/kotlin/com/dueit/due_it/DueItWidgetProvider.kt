package com.dueit.due_it

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class DueItWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_layout).apply {
                // Get data saved from Flutter
                val title = widgetData.getString("widget_title", "DueIt Status")
                val subtitle = widgetData.getString("widget_subtitle", "Loading...")

                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_subtitle, subtitle)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
