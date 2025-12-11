import abilityTest from './Ability.test';
import withTaskTest from './WithTask.test';
import withUtilsTest from './WithUtils.test';

export default function testsuite() {
  abilityTest();
  withUtilsTest();
  withTaskTest();
}