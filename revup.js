import { reverseString } from 'local:root/reverse';

export const reversedUpper = {
  reverseAndUppercase(s) {
    return reverseString(s).toLocaleUpperCase();
  },
};
