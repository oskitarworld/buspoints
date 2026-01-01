package com.app.buspoints

import android.app.Activity
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.graphics.Color
import com.google.android.gms.maps.StreetViewPanoramaView
import com.google.android.gms.maps.OnStreetViewPanoramaReadyCallback
import com.google.android.gms.maps.StreetViewPanorama
import com.google.android.gms.maps.model.LatLng

class StreetViewActivity : Activity(), OnStreetViewPanoramaReadyCallback {
    private lateinit var panoramaView: StreetViewPanoramaView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Create a container so we can overlay a "Volver al mapa" button above the panorama view
        val container = FrameLayout(this)
        container.layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )

        panoramaView = StreetViewPanoramaView(this)
        panoramaView.layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        container.addView(panoramaView)

        // Create a pill-shaped button (icon + text) to return to the map
        val buttonLayout = android.widget.LinearLayout(this)
        buttonLayout.orientation = android.widget.LinearLayout.HORIZONTAL
        buttonLayout.gravity = Gravity.CENTER_VERTICAL
        buttonLayout.setPadding((12 * resources.displayMetrics.density).toInt(), (8 * resources.displayMetrics.density).toInt(), (14 * resources.displayMetrics.density).toInt(), (8 * resources.displayMetrics.density).toInt())

        // Background: rounded pill with a pleasant color
        val pillBg = android.graphics.drawable.GradientDrawable()
        pillBg.cornerRadius = 28f * resources.displayMetrics.density
        pillBg.setColor(Color.parseColor("#FF7A59")) // warm coral
        buttonLayout.background = pillBg

        // Emoji icon (map) as a TextView to keep it playful
        val iconView = android.widget.TextView(this)
        iconView.text = "🗺️"
        iconView.textSize = 18f
        iconView.setTextColor(Color.WHITE)
        iconView.setPadding(0, 0, (8 * resources.displayMetrics.density).toInt(), 0)

        // Label
        val labelView = android.widget.TextView(this)
        labelView.text = "Volver al mapa"
        labelView.textSize = 14f
        labelView.setTextColor(Color.WHITE)
        labelView.setTypeface(labelView.typeface, android.graphics.Typeface.BOLD)

        buttonLayout.addView(iconView)
        buttonLayout.addView(labelView)

        val params = FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT)
        params.gravity = Gravity.TOP or Gravity.END
        val marginDp = (16 * resources.displayMetrics.density).toInt()
        params.setMargins(marginDp, marginDp, marginDp, marginDp)
        buttonLayout.layoutParams = params

        buttonLayout.setOnClickListener {
            finish()
        }

        // Ripple effect for touch feedback
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
            val attrs = intArrayOf(android.R.attr.selectableItemBackgroundBorderless)
            val ta = obtainStyledAttributes(attrs)
            val selectable = ta.getDrawable(0)
            ta.recycle()
            buttonLayout.foreground = selectable
        }

        container.addView(buttonLayout)

        setContentView(container)

        panoramaView.onCreate(savedInstanceState)
        panoramaView.getStreetViewPanoramaAsync(this)
    }

    override fun onStreetViewPanoramaReady(panorama: StreetViewPanorama) {
        val lat = intent?.getDoubleExtra("lat", 0.0) ?: 0.0
        val lng = intent?.getDoubleExtra("lng", 0.0) ?: 0.0
        val position = LatLng(lat, lng)
        panorama.setPosition(position)
    }

    override fun onResume() {
        super.onResume()
        if (::panoramaView.isInitialized) panoramaView.onResume()
    }

    override fun onPause() {
        if (::panoramaView.isInitialized) panoramaView.onPause()
        super.onPause()
    }

    override fun onDestroy() {
        if (::panoramaView.isInitialized) panoramaView.onDestroy()
        super.onDestroy()
    }

    override fun onLowMemory() {
        super.onLowMemory()
        if (::panoramaView.isInitialized) panoramaView.onLowMemory()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        if (::panoramaView.isInitialized) panoramaView.onSaveInstanceState(outState)
        super.onSaveInstanceState(outState)
    }
}
