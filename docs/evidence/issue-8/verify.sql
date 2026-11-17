-- Ejecutar exclusivamente sobre la base aislada creada por la fixture.
-- Ruta: cerrada, regreso confirmado y conductor liberado por el servidor.
SELECT r.status,
       r."completedAt" IS NOT NULL AS completion_recorded,
       r."returnedAt" IS NOT NULL AS return_confirmed,
       d."isAvailable" AS driver_available,
       count(s.id) AS stops,
       count(*) FILTER (WHERE s.outcome = 'SUCCESSFUL') AS delivered,
       count(*) FILTER (WHERE s.outcome = 'FAILED') AS failed,
       count(*) FILTER (WHERE s.outcome IN ('SUCCESSFUL', 'FAILED')) AS resolved
FROM public.route r
JOIN public.driver d ON d.id = r."driverId"
JOIN public."routeStop" s ON s."routeId" = r.id
WHERE r.id = 'f8541a2e-d9cb-4b09-8d9d-5c21e527cb7c'
GROUP BY r.status, r."completedAt", r."returnedAt", d."isAvailable";

-- Cada visita tiene un único intento; el fallido conserva motivo y deja el
-- pedido en reparto (sin CANCELLED ni DELIVERED) y marcado para ADMIN.
SELECT s.sequence, s.outcome, o.status AS commercial_status,
       o."requiresAdministrativeReview" AS admin_review,
       count(a.id) AS attempts,
       max(a."failureReason") AS failure_reason
FROM public."routeStop" s
JOIN public."order" o ON o.id = s."orderId"
LEFT JOIN public."deliveryAttempt" a ON a."stopId" = s.id
WHERE s."routeId" = 'f8541a2e-d9cb-4b09-8d9d-5c21e527cb7c'
GROUP BY s.sequence, s.outcome, o.status, o."requiresAdministrativeReview"
ORDER BY s.sequence;

-- Una sola reserva del conductor, liberada al confirmar el regreso.
SELECT count(*) AS reservations,
       count(*) FILTER (WHERE "releasedAt" IS NOT NULL) AS released
FROM public."driverReservation"
WHERE "routeId" = 'f8541a2e-d9cb-4b09-8d9d-5c21e527cb7c';

-- La ruta ajena no fue modificada por el chofer.
SELECT r.status, s.outcome, count(a.id) AS attempts
FROM public.route r
JOIN public."routeStop" s ON s."routeId" = r.id
LEFT JOIN public."deliveryAttempt" a ON a."stopId" = s.id
WHERE r.id = 'f8541a2e-d9cb-4b09-8d9d-5c21e527cb7d'
GROUP BY r.status, s.outcome;
