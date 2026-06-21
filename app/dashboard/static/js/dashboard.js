/**
 * SafeCity Dashboard — Minimal JS
 * Auto-refresh dashboard data every 30 seconds.
 */

(function () {
    'use strict';

    // Auto-refresh the page every 30 seconds if on the dashboard
    const isDashboard = document.querySelector('.stats-grid');
    if (isDashboard) {
        setInterval(function () {
            window.location.reload();
        }, 30000);
    }
})();
