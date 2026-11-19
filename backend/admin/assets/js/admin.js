// SABER+ COMMAND CENTER — JavaScript base

(function() {
    'use strict';

    // Toggle sidebar en móvil
    const toggle = document.getElementById('sidebarToggle');
    const sidebar = document.getElementById('sidebar');
    if (toggle && sidebar) {
        toggle.addEventListener('click', function() {
            sidebar.classList.toggle('is-open');
        });
        // Cerrar al hacer click fuera
        document.addEventListener('click', function(e) {
            if (sidebar.classList.contains('is-open') &&
                !sidebar.contains(e.target) &&
                e.target !== toggle) {
                sidebar.classList.remove('is-open');
            }
        });
    }

    // Reloj en header
    const clock = document.getElementById('clock');
    if (clock) {
        function updateClock() {
            const now = new Date();
            const h = String(now.getHours()).padStart(2, '0');
            const m = String(now.getMinutes()).padStart(2, '0');
            clock.textContent = h + ':' + m;
        }
        updateClock();
        setInterval(updateClock, 30000);
    }

    // Auto-cerrar flash messages después de 5 segundos
    document.querySelectorAll('.flash').forEach(function(el) {
        setTimeout(function() {
            el.style.transition = 'opacity 0.5s';
            el.style.opacity = '0';
            setTimeout(function() { el.remove(); }, 500);
        }, 5000);
    });

    // Confirmación en botones data-confirm
    document.querySelectorAll('[data-confirm]').forEach(function(btn) {
        btn.addEventListener('click', function(e) {
            const msg = btn.getAttribute('data-confirm');
            if (!confirm(msg)) {
                e.preventDefault();
                return false;
            }
        });
    });

    // Sorting en tablas con data-sort
    document.querySelectorAll('th[data-sort]').forEach(function(th) {
        th.style.cursor = 'pointer';
        th.addEventListener('click', function() {
            const col = th.getAttribute('data-sort');
            const url = new URL(window.location.href);
            const currentSort = url.searchParams.get('sort') || '';
            const currentDir = url.searchParams.get('dir') === 'asc' ? 'desc' : 'asc';
            url.searchParams.set('sort', col);
            url.searchParams.set('dir', currentDir);
            window.location.href = url.toString();
        });
    });

    // Búsqueda inline (input con data-search-target)
    document.querySelectorAll('[data-search-target]').forEach(function(input) {
        input.addEventListener('input', function() {
            const targetSel = input.getAttribute('data-search-target');
            const target = document.querySelector(targetSel);
            if (!target) return;
            const q = input.value.toLowerCase();
            target.querySelectorAll('tbody tr').forEach(function(row) {
                const text = row.textContent.toLowerCase();
                row.style.display = text.includes(q) ? '' : 'none';
            });
        });
    });

    // Modal genérico
    window.openModal = function(modalId) {
        const modal = document.getElementById(modalId);
        if (modal) modal.style.display = 'flex';
    };
    window.closeModal = function(modalId) {
        const modal = document.getElementById(modalId);
        if (modal) modal.style.display = 'none';
    };

    // Click fuera de modal para cerrar
    document.querySelectorAll('.modal-backdrop').forEach(function(backdrop) {
        backdrop.addEventListener('click', function(e) {
            if (e.target === backdrop) {
                backdrop.style.display = 'none';
            }
        });
    });

    // Toast simple
    window.toast = function(message, type) {
        type = type || 'info';
        const t = document.createElement('div');
        t.className = 'flash flash--' + type;
        t.style.cssText = 'position:fixed;top:20px;right:20px;z-index:9999;min-width:300px;';
        t.innerHTML = '<span>' + message + '</span>' +
                      '<button class="flash__close" onclick="this.parentElement.remove()">×</button>';
        document.body.appendChild(t);
        setTimeout(function() {
            t.style.transition = 'opacity 0.5s';
            t.style.opacity = '0';
            setTimeout(function() { t.remove(); }, 500);
        }, 3000);
    };
})();
