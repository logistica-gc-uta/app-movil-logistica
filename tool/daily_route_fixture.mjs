// Isolated synthetic data for integration_test/daily_route_test.dart.
// node tool/daily_route_fixture.mjs setup|serve|cleanup <backend-path> <owned-db-name>
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [action, backendPath, database] = process.argv.slice(2);
if (!backendPath || !/^mobile_issue[34]_[a-z0-9_]+$/.test(database ?? '')) {
  throw new Error('Provide backend path and a database named mobile_issue3_<unique suffix> or mobile_issue4_<unique suffix>');
}
const backend = resolve(backendPath);
const docker = (args, input) => execFileSync('docker', args, { input, stdio: ['pipe', 'pipe', 'pipe'] });
const pg = (args, input) => docker(['exec', '-i', 'logistica_postgres', ...args], input);
if (action === 'cleanup') {
  pg(['dropdb', '-U', 'logistica_user', '--if-exists', database]);
  console.log('Owned fixture database removed.');
} else if (action === 'serve') {
  const require = createRequire(join(backend, 'package.json'));
  require('dotenv').config({ path: join(backend, '.env'), quiet: true });
  const url = new URL(process.env.DATABASE_URL);
  url.pathname = `/${database}`;
  process.env.DATABASE_URL = url.toString();
  process.env.PORT = '3003';
  process.chdir(backend);
  await import(pathToFileURL(join(backend, 'dist/main.js')).href);
} else if (action === 'setup') {
  const schema = pg(['pg_dump', '-U', 'logistica_user', '-d', 'logistica_db', '--schema-only', '--no-owner', '--no-privileges']);
  pg(['createdb', '-U', 'logistica_user', database]);
  pg(['psql', '-U', 'logistica_user', '-d', database, '-v', 'ON_ERROR_STOP=1'], schema);
  const require = createRequire(join(backend, 'package.json'));
  const password = require('bcryptjs').hashSync('fixture-only-123', 10);
  const date = new Date(Date.now() - 5 * 3600000).toISOString().slice(0, 10);
  const route = 'f8541a2e-d9cb-4b09-8d9d-5c21e527cb7c';
  const otherRoute = 'f8541a2e-d9cb-4b09-8d9d-5c21e527cb7d';
  const rows = [];
  rows.push(`INSERT INTO public."user" (id,name,email,password,role) VALUES
    ('owner','Chofer DEMO','owner@fixture.invalid','${password}','DRIVER'),
    ('other','Otro DEMO','other@fixture.invalid','${password}','DRIVER'),
    ('admin','Admin DEMO','admin@fixture.invalid','${password}','ADMIN'),
    ('client','Cliente DEMO','client@fixture.invalid','${password}','CLIENT');`);
  rows.push(`INSERT INTO public.driver (id,"userId",vehicle,"isAvailable") VALUES ('driver','owner','DEMO',false),('other-driver','other','DEMO',false);
    INSERT INTO public.zone (id,name,code) VALUES ('zone','Zona DEMO','DEMO');
    INSERT INTO public.route (id,"driverId","zoneId",date,status) VALUES
      ('${route}','driver','zone','${date}T15:00:00Z','ASSIGNED'),
      ('${otherRoute}','other-driver','zone','${date}T15:00:00Z','ASSIGNED');
    INSERT INTO public."driverReservation" (id,"routeId","driverId","reservedAt") VALUES
      ('res-owner','${route}','driver',now()),('res-other','${otherRoute}','other-driver',now());`);
  for (let i = 1; i <= 5; i++) {
    const id = i === 5 ? otherRoute : route;
    const sequence = i === 5 ? 1 : i;
    const stop = `172458d0-8e18-42ad-87ec-9d6611a76d2${i}`;
    rows.push(`INSERT INTO public."order" (id,"userId","zoneId","routeId",status,"deliveryAddress","scheduledDeliveryDate") VALUES
      ('order-${i}','client','zone','${id}','ASSIGNED','Calle DEMO ${i}','${date}T15:00:00Z');
      INSERT INTO public."routeStop" (id,"routeId","orderId",sequence,outcome,"isLegacy") VALUES
      ('${stop}','${id}','order-${i}',${sequence},'PENDING',false);
      INSERT INTO public."orderClaim" (id,"routeId","orderId","claimedAt") VALUES ('claim-${i}','${id}','order-${i}',now());`);
  }
  pg(['psql', '-U', 'logistica_user', '-d', database, '-v', 'ON_ERROR_STOP=1'], rows.join('\n'));
  console.log('Isolated fixture ready: two drivers, four owned stops, one foreign stop.');
} else {
  throw new Error('Expected setup, serve or cleanup');
}
