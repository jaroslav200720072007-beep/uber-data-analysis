--Аналіз даних за допомогою SQL дані з Uber

--1. Написати запит який показуватиме головні метрики за допомогою яких можна щоденно дивитися 
--чи все добре з показниками та чи немає просадок по метриках

--1.1. Кількість завершених поіздок за травень, кількість скасованих за травень
SELECT COUNT(CASE WHEN status = 'completed' THEN trip_id END) AS 'Кількість завершених поіздок',
       COUNT(CASE WHEN status = 'cancelled'  THEN trip_id END) AS 'Кількість скасованих поіздок',
       SUM(CASE WHEN status = 'completed' THEN total_fare END) AS 'Загальна сума прибутку за травень',
       ROUND(AVG(CASE WHEN status = 'completed' THEN total_fare END),2) AS 'Середній чек за травень'
       
FROM trips
WHERE strftime('%m', started_at) = '05'

--1.2. Оплачені та неоплачені поіздки показує збоі оплатами карти за період травня
SELECT COUNT(CASE WHEN p.status = 'success' THEN 1 END) AS "Оплачені поіздки",
       COUNT(CASE WHEN p.payment_id  IS NULL THEN 1 END) AS "Неоплачені поіздки",
       COUNT(CASE WHEN p.status = 'failed' THEN 1 END) AS "Помилка оплати",
       COUNT(CASE WHEN p.status = 'refunded' THEN 1 END) AS "Повернення",
       
       ROUND(100.0 * COUNT(CASE WHEN p.status = 'success' THEN 1 END) / COUNT(*), 2) AS "% Успішних",
       ROUND(100.0 * COUNT(CASE WHEN p.payment_id IS NULL THEN 1 END) / COUNT(*), 2) AS "% Неоплачених",
       ROUND(100.0 * COUNT(CASE WHEN p.status = 'failed' THEN 1 END) / COUNT(*), 2) AS "% Помилок",
       ROUND(100.0 * COUNT(CASE WHEN p.status = 'refunded' THEN 1 END) / COUNT(*), 2) AS "% Повернень"
FROM trips t LEFT JOIN payments p ON t.trip_id = p.trip_id
WHERE strftime('%m', t.requested_at) = '05'

--1.3. Якість сервісу та чіткість рахуємо середні часвід моменту створеннязамовлення до моменту коли водій почав поіздку (Підзапит)
--середній час очікування авто за травень та квітень порівння

SELECT (SELECT ROUND(AVG(STRFTIME('%s', started_at) - STRFTIME('%s', requested_at) ) / 60, 2) FROM trips WHERE strftime('%m', requested_at) = '05') AS "Травень",
       (SELECT ROUND(AVG(STRFTIME('%s', started_at) - STRFTIME('%s', requested_at) ) / 60, 2) FROM trips WHERE strftime('%m', requested_at) = '04')AS "Квітень"
--Або 
WITH avg_time_all_time AS (
SELECT strftime('%m', requested_at) AS month_avg, AVG(STRFTIME('%s', started_at) - STRFTIME('%s', requested_at)) / 60 AS avg_time
FROM trips
WHERE status = 'completed' 
GROUP BY strftime('%m', requested_at)
)
SELECT ROUND(CASE WHEN month_avg = '05' THEN avg_time END,2) AS avg_time_may,
       ROUND(CASE WHEN month_avg = '04' THEN avg_time END, 2) AS avg_time_april
FROM avg_time_all_time
--Висновок час очіковання авто в травні порівнянно з часовм очікуваньом авто в квітні знизився на 0,18 хв

--2.Бізнес Аналітика

--2.1 Аналіз топ водіів та іхнього доходу 
SELECT 
d.driver_id, 
u.name, 
COUNT(t.trip_id) AS "Загальна кількість поіздок", 
COUNT(CASE WHEN t.status = 'completed' THEN 1 END) AS "Кількість завершених поіздок",
ROUND(100.0 * COUNT(c.cancel_id) / COUNT(t.trip_id), 2) AS "% CR Скасувань",
ROUND(SUM(CASE WHEN t.status = 'completed' THEN t.total_fare END), 2) AS "Загальний виторг",
ROUND(AVG(CASE WHEN t.status = 'completed' THEN t.total_fare END), 2) AS "Середній чек",
ROUND(AVG(r.rating), 2) AS "Середній рейтинг"

FROM drivers d JOIN users u ON d.user_id = u.user_id 
               JOIN trips t ON d.driver_id = t.driver_id
               LEFT JOIN cancellations c ON t.trip_id = c.trip_id
               LEFT JOIN reviews r ON t.trip_id = r.trip_id AND r.reviewee_id = u.user_id
GROUP BY d.driver_id, u.name 
ORDER BY SUM(CASE WHEN t.status = 'completed' THEN t.total_fare END) DESC

--2.1 Оцінка кожноі географічноі зони
SELECT 
l.zone_name, 
l.city, 
COUNT(t.trip_id) AS "Кількість замовлень",
ROUND(AVG(t.surge_multiplier), 2) AS "Середній коофіцієнт пікового тарифу",
ROUND(AVG(STRFTIME('%s', t.started_at) - STRFTIME('%s', t.requested_at)) / 60, 2) AS "Середній час очікування успішних поіздок",
SUM(CASE WHEN t.status = 'completed' THEN t.total_fare END) AS "Загальна виручка по регіоні",
SUM(CASE WHEN t.status = 'cancelled' THEN t.total_fare END) AS "Скільки грошей витратили через скасування",
ROUND(100.0 * COUNT(c.cancel_id) / COUNT(t.trip_id),2) AS "Відсоток скасувань у регіоні "

FROM locations l JOIN trips t ON l.location_id = t.pickup_location_id 
                 LEFT JOIN  cancellations c ON t.trip_id = c.trip_id

GROUP BY l.zone_name, l.city
HAVING COUNT(t.trip_id) >= 10
ORDER BY SUM(CASE WHEN t.status = 'cancelled' THEN t.total_fare END) DESC

--2.3 Аналіз утримання пасажирів лояльності та відтоку
WITH cte AS(
SELECT 
r.rider_id, 
u.name, 
t.trip_id, 
t.requested_at, 
t.total_fare, 
LAG(t.requested_at) OVER(PARTITION BY r.rider_id ORDER BY t.requested_at ) AS rn
FROM riders r JOIN users u ON r.user_id = u.user_id
              JOIN trips t ON r.rider_id = t.rider_id
)
SELECT 
rider_id,
COUNT(trip_id) AS "Кількість завершених поіздок",
ROUND(SUM(total_fare), 2) AS "Загальний виторг з клієнта",
MIN(requested_at) AS "Дата першоі поіздки",
MAX(requested_at) AS "Дата останьоі поіздки",
STRFTIME('%j', requested_at) -  STRFTIME('%j', rn) AS "Різниця у днях між попереднім замовленням",
ROUND(AVG(STRFTIME('%j', requested_at) -  STRFTIME('%j', rn)), 2) AS "Середній час між поіздками у днях"
FROM cte
GROUP BY rider_id
HAVING COUNT(trip_id) > 1


SELECT *
FROM trips
ORDER BY completed_at DESC