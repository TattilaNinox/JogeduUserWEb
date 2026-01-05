# Prompt for Flashcard System Audit

This prompt is designed to be given to an AI assistant to conduct a comprehensive audit of the JogEdu flashcard system.

---

**Role:** You are an Expert Software Architect and Flutter/Firebase Specialist.

**Task:** Conduct a comprehensive audit of the current Flashcard Learning System, focusing on Scalability, Cost Efficiency, and Functional Integrity for a user base of 7,000 active users.

**Context:**
The application is a Flutter Web App using Firebase (Firestore + Auth). Recent optimizations (J2) were implemented to reduce Firestore write costs by 75% (removing immediate stats updates).

**Key Files to Analyze:**
1.  `lib/services/learning_service.dart` (Core logic, DB interactions)
2.  `lib/services/deck_collection_service.dart` (Collection management)
3.  `lib/screens/flashcard_study_screen.dart` (Single deck study UI)
4.  `lib/screens/collection_study_screen.dart` (Multi-deck collection study UI)
5.  `lib/screens/deck_collection_view_screen.dart` (Collection overview UI)
6.  `lib/core/learning_algorithm.dart` (SM-2 implementation)

**Audit Objectives:**

1.  **Scalability & Cost Verification (Crucial)**
    *   Verify that evaluating a single flashcard results in **only 1 Firestore write** (the learning document itself).
    *   Confirm that `deck_stats` and `category_stats` are NOT updated on every card evaluation (to save costs).
    *   Calculate the estimated monthly Firestore write cost for 7,000 users, assuming 20 cards reviewed per user per day.
    *   Assess if the current "on-demand" stats calculation (client-side counting) allows for acceptable performance with 7,000 users.

2.  **Functional Integrity Check**
    *   **Reset Logic:** Analyze `_resetCollectionProgress` in `collection_study_screen.dart`. Does it correctly delete all learning history? Does it navigate back to the view screen to force a refresh?
    *   **Counter Loading:** Verify that `CollectionStudyScreen` loads "New/Again/Hard/Good/Easy" counters from Firestore `lastRating` fields, not from local temporary variables.
    *   **Cache Management:** Check if `Source.server` is correctly used in `DeckCollectionViewScreen` to prevent showing stale (deleted) learning statuses after a reset.

3.  **Code Quality & Best Practices**
    *   Identify any potential race conditions or unhandled exceptions in the learning flow.
    *   Check for proper resource disposal (though batch writers were removed, ensure no leaks remain).

**Output Format:**
Provide a structured report with:
*   **Executive Summary:** Pass/Fail on scalability goals.
*   **Cost Analysis:** Detailed math on writes/reads.
*   **Critical Findings:** Any bugs or severe logical flaws.
*   **Recommendations:** Concrete steps for further improvement (if any).

**Start by reviewing the files listed above.**
