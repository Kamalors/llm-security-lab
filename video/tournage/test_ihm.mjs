// node --test video/tournage/test_ihm.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { verifierActions } from './ihm.mjs';

test('refuse les champs enregistrés sur le serveur', () => {
  assert.throws(() => verifierActions([{ clic: '#entreprise' }]), /enregistr/);
  assert.throws(() => verifierActions([{ defiler: '#levels tr' }]), /enregistr/);
});
test('refuse une action inconnue', () => {
  assert.throws(() => verifierActions([{ voler: 1 }]), /inconnue/);
});
test('accepte les actions prévues', () => {
  verifierActions([{ touche: 'ArrowRight' }, { attendre: 500 }, { attendre_selecteur: '#verdict', max: 1000 }]);
});
