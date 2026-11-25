package com.karta.navigation.auto

import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.GridItem
import androidx.car.app.model.GridTemplate
import androidx.car.app.model.ItemList
import androidx.car.app.model.Template

/**
 * Driver-distraction-compliant 1-tap `GridTemplate` presenting Karta's 6 canonical
 * road hazard categories (`Police`, `Accident`, `Pothole`, `Stopped Car`, `Debris`, `Closure`).
 *
 * Selecting any tile immediately broadcasts the report across [KartaAutoStateStore]
 * into Dart's `RealtimeCrowdsourcingNotifier`, confirms via `CarToast`, and pops back
 * to [KartaNavigationScreen].
 */
class KartaHazardReportScreen(
    carContext: CarContext,
) : Screen(carContext) {

    private data class QuickHazardTile(
        val categoryWire: String,
        val severityWire: String,
        val title: String,
        val shortCode: String,
        val accentArgb: Int,
    )

    private val tiles = listOf(
        QuickHazardTile("police", "medium", "Police", "POL", KartaAutoPalette.STATUS_INFO),
        QuickHazardTile("accident", "high", "Accident", "ACC", KartaAutoPalette.STATUS_ALERT),
        QuickHazardTile("pothole", "medium", "Pothole", "POT", KartaAutoPalette.STATUS_CAUTION),
        QuickHazardTile("hidden_vehicle", "medium", "Stopped Car", "CAR", 0xFFF59E0B.toInt()),
        QuickHazardTile("road_debris", "medium", "Debris", "DEB", 0xFFA855F7.toInt()),
        QuickHazardTile("road_closure", "high", "Closure", "CLS", KartaAutoPalette.STATUS_ALERT),
    )

    override fun onGetTemplate(): Template {
        val theme = KartaAutoTheme.resolve(KartaAutoStateStore.isDarkMode.value)
        val listBuilder = ItemList.Builder()
        for (tile in tiles) {
            val icon = KartaValhallaManeuverMapper.renderBadgeIcon(
                label = tile.shortCode,
                accentArgb = tile.accentArgb,
                theme = theme,
            )
            listBuilder.addItem(
                GridItem.Builder()
                    .setTitle(tile.title)
                    .setImage(icon, GridItem.IMAGE_TYPE_LARGE)
                    .setOnClickListener {
                        KartaAutoStateStore.emitQuickReportHazard(
                            categoryWire = tile.categoryWire,
                            severityWire = tile.severityWire,
                            oppositeSide = false,
                        )
                        CarToast.makeText(
                            carContext,
                            "${tile.title} reported to Karta",
                            CarToast.LENGTH_SHORT,
                        ).show()
                        screenManager.pop()
                    }
                    .build(),
            )
        }

        return GridTemplate.Builder()
            .setTitle("Report Road Hazard")
            .setHeaderAction(Action.BACK)
            .setSingleList(listBuilder.build())
            .build()
    }
}
