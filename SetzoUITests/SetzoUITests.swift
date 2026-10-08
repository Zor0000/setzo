import XCTest

final class SetzoUITests: XCTestCase {
    private var app: XCUIApplication!

    private func waitUntilStable(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var previousFrame: CGRect?
        var stableSamples = 0

        while Date() < deadline {
            if element.exists, element.isHittable {
                let frame = element.frame
                if frame == previousFrame {
                    stableSamples += 1
                    if stableSamples >= 2 { return true }
                } else {
                    stableSamples = 0
                    previousFrame = frame
                }
            } else {
                stableSamples = 0
                previousFrame = nil
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    /// The add-exercise sheet is scrollable and may grow as new discovery
    /// tools are added above the custom field. Bring the field on-screen before
    /// typing instead of depending on a particular device height.
    private func scrollToHittable(_ element: XCUIElement, maxSwipes: Int = 5) {
        var swipes = 0
        let safeBottom = app.frame.maxY - 220
        while element.exists,
              (!element.isHittable || element.frame.maxY > safeBottom),
              swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.isHittable && element.frame.maxY <= safeBottom)
    }

    /// Add Exercise opens on the library intent; the custom field lives behind
    /// "Add your own", one tap away and never below a long catalog list.
    private func openCustomExerciseEntry() {
        let customMode = app.buttons["add-exercise-mode-custom"]
        XCTAssertTrue(customMode.waitForExistence(timeout: 3))
        scrollToHittable(customMode)
        customMode.tap()
        let exerciseField = app.textFields["new-exercise-name-field"]
        XCTAssertTrue(exerciseField.waitForExistence(timeout: 3))
        XCTAssertTrue(exerciseField.isHittable, "custom name field must be reachable without scrolling past the catalog")
    }

    private func addCustomExercise(_ name: String) {
        openCustomExerciseEntry()
        let exerciseField = app.textFields["new-exercise-name-field"]
        exerciseField.tap()
        exerciseField.typeText(name)
        app.buttons["confirm-add-exercise-button"].tap()
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UITest_ResetStore"]
        app.launch()
    }

    func testHistoryCalendarFiltersWorkoutsAndNavigatesMonths() {
        app.terminate()
        app.launchArguments = ["-seedDemo", "YES", "-seedTab", "history", "-AppleLocale", "en_US"]
        app.launch()
        let month = app.staticTexts["history-calendar-month"]
        XCTAssertTrue(month.waitForExistence(timeout: 8))
        let initialMonth = month.label
        let today = Calendar.current.component(.day, from: Date())
        let todayButton = app.buttons["history-day-\(today)"]
        XCTAssertTrue(todayButton.label.contains("2 workouts"))
        todayButton.tap()
        XCTAssertTrue(app.buttons["history-show-all"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons.matching(identifier: "history-card-toggle").count, 2)
        let selected = XCTAttachment(screenshot: app.screenshot())
        selected.name = "history-calendar-selected-day"
        selected.lifetime = .keepAlways
        add(selected)
        app.buttons["history-show-all"].tap()
        XCTAssertGreaterThan(app.buttons.matching(identifier: "history-card-toggle").count, 2)
        app.buttons["history-next-month"].tap()
        XCTAssertNotEqual(month.label, initialMonth)
        app.buttons["history-day-15"].tap()
        XCTAssertTrue(app.staticTexts["No workouts on this day."].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons.matching(identifier: "history-card-toggle").count, 0)
        app.buttons["history-previous-month"].tap()
        XCTAssertEqual(month.label, initialMonth)
        XCTAssertFalse(app.buttons["history-show-all"].exists)
        app.buttons["history-calendar-today"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "history-card-toggle").count, 2)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "history-calendar-today"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAuthScreenOffersPasswordResetAndGoogle() {
        app.terminate()
        app.launchArguments = ["UITest_ResetStore", "UITest_ShowAuth"]
        app.launch()

        XCTAssertTrue(app.buttons["forgot-password-button"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["google-sign-in-button"].exists)
        XCTAssertTrue(app.buttons["apple-sign-in-button"].exists)
        XCTAssertTrue(app.buttons["Privacy Policy"].exists)
        XCTAssertTrue(app.buttons["Terms of Use"].exists)
        // Sign-in mode must keep social buttons tappable — gating them
        // behind the age toggle is what read as "unresponsive" in review.
        XCTAssertTrue(app.buttons["google-sign-in-button"].isEnabled)
        XCTAssertTrue(app.buttons["apple-sign-in-button"].isEnabled)
        app.buttons["forgot-password-button"].tap()
        XCTAssertTrue(app.staticTexts["Reset password"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["send-reset-link-button"].exists)
    }

    func testBusyAuthScreenKeepsItsButtonsOnScreen() {
        app.terminate()
        app.launchArguments = ["UITest_ResetStore", "UITest_ShowAuth", "UITest_AuthBusy"]
        app.launch()

        let signingIn = app.buttons["Signing In…"]
        XCTAssertTrue(signingIn.waitForExistence(timeout: 6))
        XCTAssertLessThan(signingIn.frame.height, 80)
        XCTAssertTrue(app.frame.contains(signingIn.frame))
        XCTAssertFalse(app.staticTexts["Your training story, in one place"].exists)
        let google = app.buttons["google-sign-in-button"]
        XCTAssertTrue(app.frame.contains(google.frame))
        XCTAssertFalse(google.isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "busy-auth-layout"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFreeWorkoutCanAddExerciseCompleteSetAndSave() {
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 6))
        app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["start-free-workout-button"].waitForExistence(timeout: 6))
        app.buttons["start-free-workout-button"].tap()

        addCustomExercise("Push Ups")

        let repsField = app.textFields["set-reps-input"].firstMatch
        XCTAssertTrue(repsField.waitForExistence(timeout: 3))
        repsField.tap()
        repsField.typeText("12")

        app.buttons["set-done-button"].firstMatch.tap()
        app.buttons["finish-workout-button"].tap()

        XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 4))
        // Collapsed card shows date + split only; expanding reveals exercises.
        XCTAssertTrue(app.staticTexts["1 set · Free Workout · local"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Push Ups"].exists)
        app.buttons["history-card-toggle"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Push Ups"].waitForExistence(timeout: 3))
    }

    func testExerciseAndSetDeletionUseTheRequestedConfirmationRules() {
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 6))
        app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["start-free-workout-button"].waitForExistence(timeout: 6))
        app.buttons["start-free-workout-button"].tap()
        addCustomExercise("Push Ups")

        // Exercise removal always asks, even before any set is filled in.
        let removeExercise = app.buttons["remove-exercise-button"].firstMatch
        XCTAssertTrue(waitUntilStable(removeExercise))
        removeExercise.tap()
        XCTAssertTrue(app.staticTexts["Remove exercise?"].waitForExistence(timeout: 2))
        app.buttons["Keep It"].tap()

        // A newly added empty set disappears directly.
        let addSet = app.buttons["Add Set"]
        XCTAssertTrue(waitUntilStable(addSet))
        addSet.tap()
        let repsFields = app.textFields.matching(identifier: "set-reps-input")
        XCTAssertTrue(repsFields.element(boundBy: 1).waitForExistence(timeout: 2))
        let removeSet = app.buttons.matching(identifier: "remove-set-button").element(boundBy: 1)
        XCTAssertTrue(waitUntilStable(removeSet))
        removeSet.tap()
        XCTAssertFalse(repsFields.element(boundBy: 1).waitForExistence(timeout: 1))
        XCTAssertFalse(app.staticTexts["Remove set?"].exists)

        // Once the set has content, the same action requires confirmation.
        addSet.tap()
        let secondReps = app.textFields.matching(identifier: "set-reps-input").element(boundBy: 1)
        secondReps.tap()
        secondReps.typeText("8")
        XCTAssertTrue(waitUntilStable(removeSet))
        removeSet.tap()
        XCTAssertTrue(app.staticTexts["Remove set?"].waitForExistence(timeout: 2))
    }

    func testCustomRemarkCanBeTypedForASet() {
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 6))
        app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["start-free-workout-button"].waitForExistence(timeout: 6))
        app.buttons["start-free-workout-button"].tap()
        addCustomExercise("Push Ups")

        app.buttons["set-type-button"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Add Custom Remark"].waitForExistence(timeout: 2))
        app.buttons["Add Custom Remark"].tap()
        let remarkField = app.textFields["e.g. Slow eccentric"]
        XCTAssertTrue(remarkField.waitForExistence(timeout: 2))
        remarkField.tap()
        remarkField.typeText("Pause at the bottom")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Pause at the bottom"].waitForExistence(timeout: 2))
    }

    func testRoutineDeletionIsVisibleAndRequiresConfirmation() {
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 6))
        app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["start-free-workout-button"].waitForExistence(timeout: 6))
        app.buttons["start-free-workout-button"].tap()
        addCustomExercise("Push Ups")

        let saveRoutine = app.buttons["save-routine-button"]
        XCTAssertTrue(saveRoutine.waitForExistence(timeout: 3))
        saveRoutine.tap()
        let routineName = app.textFields["e.g. Chris's Leg Day"]
        XCTAssertTrue(routineName.waitForExistence(timeout: 2))
        routineName.tap()
        routineName.typeText("Quick Push")
        app.buttons["Save"].tap()

        app.buttons["Discard workout"].tap()
        XCTAssertTrue(app.buttons["Discard Workout"].waitForExistence(timeout: 2))
        app.buttons["Discard Workout"].tap()

        let deleteRoutine = app.buttons["delete-routine-button"]
        XCTAssertTrue(deleteRoutine.waitForExistence(timeout: 3))
        deleteRoutine.tap()
        XCTAssertTrue(app.staticTexts["Delete routine?"].waitForExistence(timeout: 2))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Quick Push"].exists)

        deleteRoutine.tap()
        app.buttons["Delete Routine"].tap()
        XCTAssertFalse(app.staticTexts["Quick Push"].waitForExistence(timeout: 1))
    }

    func testSettingsOpensFromGearAndShowsAccountControls() {
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 6))
        app.buttons["settings-button"].tap()

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Local — saved on this iPhone"].exists)
        XCTAssertTrue(app.buttons["delete-workout-data-button"].exists)
        XCTAssertTrue(app.buttons["Pounds (lb)"].exists)

        // Unit toggle flips the log screen's weight field label.
        app.buttons["Pounds (lb)"].tap()
        app.buttons["Close settings"].tap()
        app.buttons["Today"].tap()
        app.buttons["start-free-workout-button"].tap()
        openCustomExerciseEntry()
        app.buttons["Weight + Reps"].tap()
        let exerciseField = app.textFields["new-exercise-name-field"]
        exerciseField.tap()
        exerciseField.typeText("Bench Press")
        app.buttons["confirm-add-exercise-button"].tap()
        XCTAssertTrue(app.staticTexts["LB"].waitForExistence(timeout: 3))
    }

    func testProgressSwitchesBetweenStatsAndHistoryAndRemembersSelection() {
        XCTAssertTrue(app.buttons["Progress"].waitForExistence(timeout: 6))
        app.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Sessions"].waitForExistence(timeout: 3))

        app.buttons["History"].tap()
        XCTAssertTrue(app.buttons["Set Up Sync"].waitForExistence(timeout: 3))

        app.buttons["main-tab-today"].tap()
        app.buttons["Progress"].tap()
        XCTAssertTrue(app.buttons["Set Up Sync"].waitForExistence(timeout: 3))
    }

    func testIronFuelGatesFirstUseAndPassportCanBeDeleted() {
        XCTAssertTrue(app.buttons["IronFuel"].waitForExistence(timeout: 6))
        app.buttons["IronFuel"].tap()
        XCTAssertTrue(app.buttons["create-nutrition-passport-button"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["fuel-buddy-submit-button"].exists)

        app.terminate()
        app.launchArguments = ["UITest_ResetStore", "UITest_IronFuelPassport", "ready"]
        app.launch()
        app.buttons["IronFuel"].tap()
        XCTAssertTrue(app.buttons["edit-nutrition-passport-button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["fuel-buddy-request-field"].exists)
        app.buttons["delete-nutrition-passport-button"].tap()
        XCTAssertTrue(app.buttons["Delete Passport"].waitForExistence(timeout: 2))
        app.buttons["Delete Passport"].tap()
        XCTAssertTrue(app.buttons["create-nutrition-passport-button"].waitForExistence(timeout: 3))
    }

    func testIronFuelReturnsCompatibleMealFromReadyPassport() {
        app.terminate()
        app.launchArguments = ["UITest_ResetStore", "UITest_IronFuelPassport", "ready", "UITest_IronFuelState", "generated"]
        app.launch()
        app.buttons["IronFuel"].tap()

        let requestField = app.textFields["fuel-buddy-request-field"]
        XCTAssertTrue(requestField.waitForExistence(timeout: 3))
        requestField.tap()
        requestField.typeText("Indian dinner")
        app.buttons["fuel-buddy-submit-button"].tap()

        XCTAssertTrue(app.staticTexts["Paneer Bhurji"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Vegetable Pulao"].exists)
        XCTAssertTrue(app.staticTexts["Masoor Dal"].exists)
        XCTAssertFalse(app.staticTexts["On-device"].exists)
    }

    func testIronFuelScreenshotRequestsAndStaleResultClearing() {
        app.terminate()
        app.launchArguments = ["UITest_ResetStore", "UITest_IronFuelPassport", "omnivore", "UITest_IronFuelState", "generated"]
        app.launch()
        app.buttons["IronFuel"].tap()
        let requestField = app.textFields["fuel-buddy-request-field"]
        XCTAssertTrue(requestField.waitForExistence(timeout: 3))
        requestField.tap()
        requestField.typeText("Quick egg rice")
        app.buttons["fuel-buddy-submit-button"].tap()
        XCTAssertTrue(app.staticTexts["Egg Fried Rice"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Chana masala with rice"].exists)
        XCTAssertTrue(app.keyboards.allElementsBoundByIndex.isEmpty)
        app.swipeUp()
        let eggShot = XCTAttachment(screenshot: app.screenshot())
        eggShot.name = "Quick egg rice matches eggs and rice"
        eggShot.lifetime = .keepAlways
        add(eggShot)
        requestField.tap()
        // Insert text so this assertion does not depend on the cursor location
        // after scrolling back to a multiline text field.
        requestField.typeText(" extra")
        XCTAssertFalse(app.staticTexts["Egg Fried Rice"].exists, "Editing must clear old results")
        app.terminate()
        app.launch()
        app.buttons["IronFuel"].tap()
        XCTAssertTrue(requestField.waitForExistence(timeout: 3))
        requestField.tap()
        requestField.typeText("Heavy breakfast")
        app.buttons["fuel-buddy-submit-button"].tap()
        XCTAssertTrue(app.staticTexts["Paneer Bhurji with Toast"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["No compatible result"].exists)
        app.swipeUp()
        let breakfastShot = XCTAttachment(screenshot: app.screenshot())
        breakfastShot.name = "Heavy breakfast has compatible options"
        breakfastShot.lifetime = .keepAlways
        add(breakfastShot)
    }

    func testIronFuelLiveGuestGeneration() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["IRONFUEL_LIVE_TESTS"] == "1", "Opt-in live Groq integration")
        for query in ["Quick Indian dinner", "Protein rich breakfast", "Quick egg rice", "Heavy breakfast"] {
            app.terminate()
            app.launchArguments = ["UITest_ResetStore", "UITest_IronFuelPassport", "omnivore"]
            app.launch()
            app.buttons["IronFuel"].tap()
            let field = app.textFields["fuel-buddy-request-field"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(query)
            app.buttons["fuel-buddy-submit-button"].tap()
            let first = app.staticTexts["fuel-buddy-dish-name-0"]
            XCTAssertTrue(first.waitForExistence(timeout: 40), "Live AI should generate at least one dish")
            XCTAssertFalse(app.staticTexts["No compatible result"].exists)
            let count = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fuel-buddy-dish-name-")).count
            XCTAssertTrue((1...5).contains(count))
            app.swipeUp()
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Live AI guest - \(query)"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }

    func testPassportPregnancyVisibilityAndClearingWhenSexChanges() {
        app.terminate()
        app.launchArguments = ["UITest_ResetStore", "UITest_IronFuelPassport", "ready"]
        app.launch()
        app.buttons["IronFuel"].tap()
        app.buttons["edit-nutrition-passport-button"].tap()
        app.buttons["passport-sex-context-picker"].tap()
        app.buttons["Female"].tap()
        for _ in 0..<3 { app.buttons["passport-continue-button"].tap() }
        let pregnancy = app.switches["passport-pregnancy-toggle"]
        XCTAssertTrue(pregnancy.waitForExistence(timeout: 2))
        pregnancy.tap()
        for _ in 0..<3 { app.buttons["Back"].tap() }
        app.buttons["passport-sex-context-picker"].tap()
        app.buttons["Male"].tap()
        for _ in 0..<3 { app.buttons["passport-continue-button"].tap() }
        XCTAssertFalse(pregnancy.exists)
        app.buttons["save-nutrition-passport-button"].tap()
        XCTAssertTrue(app.buttons["fuel-buddy-submit-button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["edit-nutrition-passport-button"].exists)
        XCTAssertFalse(app.staticTexts["Use your care plan"].exists)
    }

    func testHistoryCardOpensEditSheetAndSavesChanges() {
        // Log a quick workout first.
        app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["start-free-workout-button"].waitForExistence(timeout: 6))
        app.buttons["start-free-workout-button"].tap()
        addCustomExercise("Push Ups")
        let repsField = app.textFields["set-reps-input"].firstMatch
        XCTAssertTrue(repsField.waitForExistence(timeout: 3))
        repsField.tap()
        repsField.typeText("12")
        app.buttons["set-done-button"].firstMatch.tap()
        app.buttons["finish-workout-button"].tap()

        // Expand the card → exercises drop down → pencil opens the edit sheet →
        // change reps → save → expanded card updates.
        let cardToggle = app.buttons["history-card-toggle"].firstMatch
        XCTAssertTrue(cardToggle.waitForExistence(timeout: 4))
        cardToggle.tap()
        XCTAssertTrue(app.staticTexts["Push Ups"].waitForExistence(timeout: 3))
        app.buttons["edit-session-button"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Edit Session"].waitForExistence(timeout: 3))
        let editReps = app.textFields["edit-reps-input"].firstMatch
        editReps.doubleTap() // select-all, so typing replaces "12"
        editReps.typeText("0")
        app.buttons["save-session-edits-button"].tap()
        XCTAssertTrue(app.staticTexts["Edit Session"].exists, "Rejected edits must keep the sheet open")
        editReps.doubleTap()
        editReps.typeText("15")
        app.buttons["save-session-edits-button"].tap()

        XCTAssertTrue(app.staticTexts["BW x 15"].waitForExistence(timeout: 4))
    }

    // MARK: Run tab

    /// The Run tab is a manual logger: pick the kind, type time (required) and
    /// optionally distance/elevation, save into History.
    private func openRunTab() {
        XCTAssertTrue(app.buttons["Run"].waitForExistence(timeout: 6))
        app.buttons["Run"].tap()
        XCTAssertTrue(app.buttons["run-kind-run"].waitForExistence(timeout: 4))
    }

    /// Swipe up until `element` can be tapped, for content that lands below
    /// the fold on compact devices or at large text sizes.
    private func scrollUntilHittable(_ element: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        while element.exists, !element.isHittable, swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    private func typeInto(_ identifier: String, _ text: String) {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(text)
    }

    func testRunTabSelectsRunOrWalkAndSavesManually() {
        openRunTab()

        // Both kinds are offered, and the save button follows the selection.
        XCTAssertTrue(app.buttons["run-kind-walk"].exists)
        XCTAssertEqual(app.buttons["save-manual-cardio-button"].label, "Save Run")
        app.buttons["run-kind-walk"].tap()
        XCTAssertEqual(app.buttons["save-manual-cardio-button"].label, "Save Walk")
        app.buttons["run-kind-run"].tap()

        typeInto("run-minutes-field", "30")
        typeInto("run-distance-field", "3")
        app.buttons["Done"].tap()

        app.buttons["save-manual-cardio-button"].tap()
        XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 4))
        let subtitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3.00 km")).firstMatch
        XCTAssertTrue(subtitle.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["history-card-toggle"].firstMatch.label.contains("Run"))
    }

    func testLargeRunInputIsRejectedWithAnExplanation() {
        openRunTab()
        typeInto("run-minutes-field", "999999999999999999")
        app.buttons["Done"].tap()
        XCTAssertFalse(app.buttons["save-manual-cardio-button"].isEnabled)
        XCTAssertTrue(app.staticTexts["Enter 0.1–1,440 minutes."].waitForExistence(timeout: 3))
    }

    func testTerrainChipsSelectAndClear() {
        openRunTab()

        let trail = app.buttons["run-terrain-trail"]
        XCTAssertTrue(trail.waitForExistence(timeout: 3))
        trail.tap()
        XCTAssertTrue(trail.isSelected)
        // Tapping the active chip clears it again — terrain is optional context.
        trail.tap()
        XCTAssertFalse(trail.isSelected)
    }

    /// The calorie estimate needs a body weight first; once set in Settings,
    /// the preview shows the ACSM figure for what is typed (5 km in 30 min at
    /// 70 kg ≈ 387 kcal).
    func testBodyWeightSettingDrivesTheCaloriePreview() {
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 6))
        app.buttons["settings-button"].tap()
        let weightField = app.textFields["body-weight-field"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 4))
        weightField.tap()
        weightField.typeText("70")
        app.buttons["Close settings"].tap()

        openRunTab()
        typeInto("run-minutes-field", "30")
        typeInto("run-distance-field", "5")
        app.buttons["Done"].tap()

        let estimate = app.staticTexts["run-calorie-estimate"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 3))
        XCTAssertTrue(estimate.label.contains("387"), "expected the ACSM estimate in '\(estimate.label)'")
    }

    func testSuggestedWorkoutWizardStartsWorkoutAndPreventsOverwrite() {
        XCTAssertTrue(app.staticTexts["Split Type"].waitForExistence(timeout: 6))
        app.buttons["split-ppl"].tap()
        app.buttons["Push"].tap()

        XCTAssertTrue(app.buttons["start-suggested-workout-button"].waitForExistence(timeout: 3))
        app.buttons["start-suggested-workout-button"].tap()

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Barbell Bench Press"].waitForExistence(timeout: 3))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Seated DB Shoulder Press"].waitForExistence(timeout: 3))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Overhead Tricep Extension"].waitForExistence(timeout: 3))

        app.buttons["Workouts"].tap()
        XCTAssertTrue(app.staticTexts["Workout in progress"].waitForExistence(timeout: 3))
        app.buttons["start-suggested-workout-button"].tap()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Barbell Bench Press"].waitForExistence(timeout: 3))
    }

    // MARK: Add Exercise

    private func startFreeWorkout() {
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 6))
        app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["start-free-workout-button"].waitForExistence(timeout: 6))
        app.buttons["start-free-workout-button"].tap()
        XCTAssertTrue(app.buttons["add-exercise-mode-browse"].waitForExistence(timeout: 3))
    }

    func testAddExerciseMuscleFilterStaysCompactAndOpensFullBrowser() {
        startFreeWorkout()

        // A free workout has no target muscle, so the library opens on the hint.
        XCTAssertFalse(app.buttons["browse-all-exercises-button"].exists)
        app.buttons["Chest exercises"].tap()

        // Inline preview is bounded: a handful of rows plus a "See all" affordance.
        let seeAll = app.buttons["browse-all-exercises-button"]
        XCTAssertTrue(seeAll.waitForExistence(timeout: 3))
        let inlineRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'exercise-template-'"))
        XCTAssertLessThanOrEqual(inlineRows.count, 5)
        XCTAssertTrue(seeAll.label.contains("chest"))

        // The custom entry is still reachable with no long catalog scroll.
        let customMode = app.buttons["add-exercise-mode-custom"]
        XCTAssertTrue(customMode.isHittable)

        // The rest of the catalog lives in a dedicated scroller.
        seeAll.tap()
        XCTAssertTrue(app.buttons["close-exercise-browser-button"].waitForExistence(timeout: 3))
        let browserRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'browse-exercise-'"))
        XCTAssertGreaterThan(browserRows.count, 5)
        app.buttons["browse-exercise-Incline Dumbbell Press"].tap()

        XCTAssertFalse(app.buttons["close-exercise-browser-button"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Incline Dumbbell Press"].waitForExistence(timeout: 3))
    }

    func testAddExerciseSearchSelectsFromPreviewAndKeepsContextAcrossIntents() {
        startFreeWorkout()

        let search = app.textFields["exercise-template-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("walking lunge")
        let row = app.buttons["exercise-template-Walking Lunges"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))

        // Switching to "Add your own" and back keeps the typed query.
        app.buttons["add-exercise-mode-custom"].tap()
        XCTAssertTrue(app.textFields["new-exercise-name-field"].waitForExistence(timeout: 2))
        XCTAssertFalse(row.exists)
        app.buttons["add-exercise-mode-browse"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        XCTAssertEqual(app.textFields["exercise-template-search-field"].value as? String, "walking lunge")

        row.tap()
        XCTAssertTrue(app.staticTexts["Walking Lunges"].waitForExistence(timeout: 3))

        // A nonsense query shows the empty state rather than nothing.
        app.buttons["show-add-exercise-button"].tap()
        let search2 = app.textFields["exercise-template-search-field"]
        XCTAssertTrue(search2.waitForExistence(timeout: 3))
        search2.tap()
        search2.typeText("zzzz")
        XCTAssertTrue(app.staticTexts["No matching exercises"].waitForExistence(timeout: 2))
    }

    func testAddExerciseCloseDismissesTheCard() {
        startFreeWorkout()
        addCustomExercise("Push Ups")
        app.buttons["show-add-exercise-button"].tap()
        XCTAssertTrue(app.buttons["add-exercise-mode-browse"].waitForExistence(timeout: 2))

        app.buttons["close-add-exercise-button"].tap()
        XCTAssertFalse(app.buttons["add-exercise-mode-browse"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["show-add-exercise-button"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Push Ups"].exists)
    }

    func testSplitPickerShowsProgramCardsAndFinderCallout() {
        XCTAssertTrue(app.staticTexts["Split Type"].waitForExistence(timeout: 6))
        for id in ["split-full-body", "split-ppl", "split-upper-lower", "split-single-muscle"] {
            XCTAssertTrue(app.buttons[id].exists, "missing program card \(id)")
        }
        XCTAssertTrue(app.buttons["split-free-workout-button"].exists)
        XCTAssertEqual(app.buttons["split-ppl"].label, "PPL")
        XCTAssertTrue(app.buttons["split-ppl"].value as? String == "Push, pull and legs on rotating days. 3–6 days / week")

        // The finder callout sits after the last split, not above them.
        let callout = app.buttons["exercise-finder-entry-button"]
        XCTAssertTrue(callout.exists)
        XCTAssertGreaterThan(callout.frame.minY, app.buttons["split-single-muscle"].frame.maxY)

        // Every card still leads into the existing wizard.
        app.buttons["split-single-muscle"].tap()
        XCTAssertTrue(app.staticTexts["Training Day"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Chest"].exists)
        app.buttons["Single Muscle"].tap()
        XCTAssertTrue(app.staticTexts["Split Type"].waitForExistence(timeout: 3))

        app.buttons["split-full-body"].tap()
        XCTAssertTrue(app.buttons["start-suggested-workout-button"].waitForExistence(timeout: 3))
        app.buttons["Full Body"].tap()
        XCTAssertTrue(app.staticTexts["Split Type"].waitForExistence(timeout: 3))

        scrollUntilHittable(callout)
        callout.tap()
        XCTAssertTrue(app.buttons["exercise-finder-muscle-chest"].waitForExistence(timeout: 3))
        app.buttons["close-exercise-finder-button"].tap()
        XCTAssertTrue(app.staticTexts["Split Type"].waitForExistence(timeout: 3))
    }

    func testExerciseFinderStartsFromMuscleAndAddsItsMatch() {
        XCTAssertTrue(app.buttons["exercise-finder-entry-button"].waitForExistence(timeout: 6))
        app.buttons["exercise-finder-entry-button"].tap()

        XCTAssertTrue(app.buttons["exercise-finder-muscle-shoulders"].waitForExistence(timeout: 3))
        app.buttons["exercise-finder-muscle-shoulders"].tap()
        app.buttons["find-best-exercise-button"].tap()

        let addRecommendation = app.buttons["add-recommended-exercise-button"]
        XCTAssertTrue(addRecommendation.waitForExistence(timeout: 6))

        // The pick is relevance-weighted and varied, so read whatever was
        // matched rather than expecting a fixed catalog entry.
        let resultName = app.staticTexts["exercise-finder-result-name"]
        XCTAssertTrue(resultName.waitForExistence(timeout: 2))
        let matchedName = resultName.label
        XCTAssertFalse(matchedName.isEmpty)
        XCTAssertTrue(app.buttons["find-another-exercise-button"].exists)

        addRecommendation.tap()

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts[matchedName].waitForExistence(timeout: 4))
    }

    func testExerciseFinderTryAnotherAvoidsImmediateRepeat() {
        XCTAssertTrue(app.buttons["exercise-finder-entry-button"].waitForExistence(timeout: 6))
        app.buttons["exercise-finder-entry-button"].tap()

        XCTAssertTrue(app.buttons["exercise-finder-muscle-chest"].waitForExistence(timeout: 3))
        app.buttons["exercise-finder-muscle-chest"].tap()
        app.buttons["find-best-exercise-button"].tap()

        let resultName = app.staticTexts["exercise-finder-result-name"]
        XCTAssertTrue(resultName.waitForExistence(timeout: 6))
        let first = resultName.label

        app.buttons["find-another-exercise-button"].tap()
        let changed = NSPredicate(format: "label != %@", first)
        expectation(for: changed, evaluatedWith: resultName)
        waitForExpectations(timeout: 6)
        XCTAssertNotEqual(resultName.label, first)

        // Switching muscle groups resets to the idle state for the new pool.
        app.buttons["exercise-finder-muscle-back"].tap()
        XCTAssertTrue(app.buttons["find-best-exercise-button"].waitForExistence(timeout: 3))
        XCTAssertFalse(resultName.exists)

        app.buttons["close-exercise-finder-button"].tap()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 4))
    }
}
