-- Ejecutar exclusivamente sobre la base aislada creada por la fixture.
SELECT r.status, r."returnedAt" IS NOT NULL AS return_confirmed,
       d."isAvailable", count(s.id) AS total,
       count(*) FILTER (WHERE s.outcome = 'SUCCESSFUL') AS delivered,
       count(*) FILTER (WHERE s.outcome IN ('SUCCESSFUL', 'FAILED')) AS resolved,
       round(100.0 * count(*) FILTER (WHERE s.outcome = 'SUCCESSFUL') /
             nullif(count(s.id), 0), 0) AS delivered_percent
FROM public.route r
JOIN public.driver d ON d.id = r."driverId"
JOIN public."routeStop" s ON s."routeId" = r.id
WHERE r.id = 'f8541a2e-d9cb-4b09-8d9d-5c21e527cb7c'
GROUP BY r.status, r."returnedAt", d."isAvailable";

SELECT s.sequence, s.outcome, o.status AS commercial_status,
       count(a.id) FILTER (WHERE a.outcome = 'FAILED') AS failed_attempts
FROM public."routeStop" s
JOIN public."order" o ON o.id = s."orderId"
LEFT JOIN public."deliveryAttempt" a ON a."stopId" = s.id
WHERE s."routeId" = 'f8541a2e-d9cb-4b09-8d9d-5c21e527cb7c'
GROUP BY s.sequence, s.outcome, o.status
ORDER BY s.sequence;

SELECT count(*) AS reservations,
       count(*) FILTER (WHERE "releasedAt" IS NOT NULL) AS released
FROM public."driverReservation"
WHERE "routeId" = 'f8541a2e-d9cb-4b09-8d9d-5c21e527cb7c';
